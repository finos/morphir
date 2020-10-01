module Morphir.IR.Type.Constrain.Pattern exposing (..)

import AssocList as Dict exposing (Dict)
import Morphir.IR.Literal as Literal
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.SDK.Common as SDK
import Morphir.IR.SDK.List as List
import Morphir.IR.Source as Source
import Morphir.IR.Type as IR
import Morphir.IR.Type.Error as Error
import Morphir.IR.Type.Instantiate as Instantiate
import Morphir.IR.Type.Type as Type exposing (Constraint(..), Type, Variable)
import Morphir.IR.Value as Value exposing (Pattern)


{-| The constraints are stored in reverse order so that adding a new constraint is O(1) and we can reverse it at some
later time.
-}
type alias State =
    { headers : Header
    , vars : List Variable
    , revCons : List Constraint
    }


type alias Header =
    Dict Name (Source.Located Type)


add : Value.Pattern Source.Region -> Error.PExpected Type -> State -> State
add pattern expectation state =
    case pattern of
        Value.WildcardPattern region ->
            state

        Value.AsPattern region realPattern name ->
            addToHeaders region name expectation state
                |> add realPattern expectation

        --Value.TuplePattern region (List (Pattern a))
        --Value.ConstructorPattern region FQName (List (Pattern a))
        Value.EmptyListPattern region ->
            let
                entryVar =
                    Type.mkFlexVar

                entryType =
                    Type.VarN entryVar

                listType =
                    Type.AppN (SDK.toFQName List.moduleName "List") [ entryType ]

                listCon =
                    CPattern region Error.PList listType expectation
            in
            State state.headers (entryVar :: state.vars) (listCon :: state.revCons)

        Value.HeadTailPattern region headPattern tailPattern ->
            let
                entryVar =
                    Type.mkFlexVar

                entryType =
                    Type.VarN entryVar

                listType =
                    Type.AppN (SDK.toFQName List.moduleName "List") [ entryType ]

                headExpectation =
                    Error.PNoExpectation entryType

                tailExpectation =
                    Error.PFromContext region Error.PTail listType

                newState =
                    state
                        |> add headPattern headExpectation
                        |> add tailPattern tailExpectation

                listCon =
                    CPattern region Error.PList listType expectation
            in
            State newState.headers (entryVar :: newState.vars) (listCon :: newState.revCons)

        Value.LiteralPattern region literal ->
            let
                literalCon =
                    case literal of
                        Literal.BoolLiteral _ ->
                            CPattern region Error.PBool Type.bool expectation

                        Literal.CharLiteral _ ->
                            CPattern region Error.PChr Type.char expectation

                        Literal.StringLiteral _ ->
                            CPattern region Error.PStr Type.string expectation

                        Literal.IntLiteral _ ->
                            CPattern region Error.PInt Type.int expectation

                        Literal.FloatLiteral _ ->
                            -- Floats should not be allowed in pattern matches, this is a temporary fix
                            Debug.todo "floats should not be allowed"
            in
            State state.headers state.vars (literalCon :: state.revCons)

        Value.UnitPattern region ->
            let
                unitCon =
                    CPattern region Error.PUnit Type.UnitN expectation
            in
            State state.headers state.vars (unitCon :: state.revCons)

        other ->
            Debug.todo ("Unhandled case: " ++ Debug.toString other)


emptyState : State
emptyState =
    State Dict.empty [] []


addToHeaders : Source.Region -> Name -> Error.PExpected Type -> State -> State
addToHeaders region name expectation state =
    let
        tipe =
            getType expectation

        newHeaders =
            Dict.insert name (Source.At region tipe) state.headers
    in
    State newHeaders state.vars state.revCons


getType : Error.PExpected Type -> Type
getType expectation =
    case expectation of
        Error.PNoExpectation tipe ->
            tipe

        Error.PFromContext _ _ tipe ->
            tipe



-- CONSTRAIN CONSTRUCTORS
--addCtor : Source.Region -> ModuleName -> Name -> List Name -> Name -> List (Pattern Source.Region) -> Error.PExpected Type -> State -> State
--addCtor region home typeName typeVarNames ctorName args expectation state =
--    let
--        varPairs : List ( Name, Variable )
--        varPairs =
--            typeVarNames
--                |> List.map
--                    (\varName ->
--                        ( varName, Type.nameToFlex varName )
--                    )
--
--        typePairs : List ( Name, Type )
--        typePairs =
--            varPairs
--                |> List.map (\( varName, tpe ) -> ( varName, Type.VarN tpe ))
--
--        freeVarDict : Dict Name Type
--        freeVarDict =
--            Dict.fromList typePairs
--
--        newState =
--            args
--                |> List.foldl
--                    (\nextArgPattern ( index, stateSoFar ) ->
--                        ( index + 1
--                        , addCtorArg region ctorName freeVarDict stateSoFar ( index, tpe, nextArgPattern )
--                        )
--                    )
--                    ( 0, state )
--
--        ctorType =
--            Type.AppN home typeName (typePairs |> List.map Tuple.second)
--
--        ctorCon =
--            CPattern region (Error.PCtor ctorName) ctorType expectation
--    in
--    { headers = newState.headers
--    , vars = (varPairs |> List.map Tuple.second) ++ newState.vars
--    , revCons = ctorCon :: newState.revCons
--    }


addCtorArg : Source.Region -> Name -> Dict Name Type -> State -> ( Int, IR.Type Source.Region, Pattern Source.Region ) -> State
addCtorArg region ctorName freeVarDict state ( index, srcType, pattern ) =
    let
        tipe =
            Instantiate.fromSrcType freeVarDict srcType

        expectation =
            Error.PFromContext region (Error.PCtorArg ctorName index) tipe
    in
    add pattern expectation state
