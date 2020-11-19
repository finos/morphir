module Morphir.Value.Interpreter exposing (..)

import Dict exposing (Dict)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Path exposing (Path)
import Morphir.IR.Value as Value exposing (Pattern, Value)
import Morphir.ListOfResults as ListOfResults
import Morphir.Value.Error exposing (Error(..), PatternMismatch(..))
import Morphir.Value.Native as Native


type alias FQN =
    ( Path, Path, Name )


type alias State =
    { references : Dict FQN Reference
    , variables : Variables
    , argumentsReversed : List (Value () ())
    }


type alias Variables =
    Dict Name (Value () ())


type Reference
    = NativeReference Native.Function
    | ValueReference (Value () ())


evaluate : Dict FQN Reference -> Value () () -> Result Error (Value () ())
evaluate references value =
    let
        initialState : State
        initialState =
            State references Dict.empty []
    in
    evaluateValue initialState value


evaluateValue : State -> Value () () -> Result Error (Value () ())
evaluateValue state value =
    case value of
        Value.Variable _ varName ->
            state.variables
                |> Dict.get varName
                |> Result.fromMaybe (VariableNotFound varName)

        Value.Reference _ ((FQName packageName moduleName localName) as fQName) ->
            state.references
                |> Dict.get ( packageName, moduleName, localName )
                |> Result.fromMaybe (ReferenceNotFound fQName)
                |> Result.andThen
                    (\reference ->
                        case reference of
                            NativeReference nativeFunction ->
                                nativeFunction (evaluateValue state) (List.reverse state.argumentsReversed)

                            ValueReference referredValue ->
                                evaluateValue state referredValue
                    )

        Value.Apply _ function argument ->
            evaluateValue
                { state
                    | argumentsReversed =
                        argument :: state.argumentsReversed
                }
                function

        Value.Lambda _ argumentPattern body ->
            state.argumentsReversed
                |> List.head
                |> Result.fromMaybe NoArgumentToPass
                |> Result.andThen
                    (\argumentValue ->
                        evaluatePattern argumentPattern argumentValue
                            |> Result.mapError LambdaArgumentDidNotMatch
                    )
                |> Result.andThen
                    (\argumentVariables ->
                        evaluateValue
                            { state
                                | variables =
                                    Dict.union argumentVariables state.variables
                            }
                            body
                    )

        _ ->
            Ok value


evaluatePattern : Pattern () -> Value () () -> Result PatternMismatch Variables
evaluatePattern pattern value =
    case pattern of
        Value.WildcardPattern _ ->
            Ok Dict.empty

        Value.AsPattern _ subjectPattern alias ->
            evaluatePattern subjectPattern value
                |> Result.map
                    (\subjectVariables ->
                        subjectVariables
                            |> Dict.insert alias value
                    )

        Value.TuplePattern _ elemPatterns ->
            case value of
                Value.Tuple _ elemValues ->
                    let
                        patternLength =
                            List.length elemPatterns

                        valueLength =
                            List.length elemValues
                    in
                    if patternLength == valueLength then
                        List.map2 evaluatePattern elemPatterns elemValues
                            |> ListOfResults.liftAllErrors
                            |> Result.mapError TupleMismatch
                            |> Result.map (List.foldl Dict.union Dict.empty)

                    else
                        Err (TupleElemCountMismatch patternLength valueLength)

                _ ->
                    Err (TupleExpected value)

        Value.ConstructorPattern _ ctorPatternFQName argPatterns ->
            let
                uncurry : Value ta va -> ( Value ta va, List (Value ta va) )
                uncurry v =
                    case v of
                        Value.Apply _ f a ->
                            let
                                ( nestedV, nestedArgs ) =
                                    uncurry f
                            in
                            ( nestedV, nestedArgs ++ [ a ] )

                        _ ->
                            ( v, [] )

                ( ctorValue, argValues ) =
                    uncurry value
            in
            case ctorValue of
                Value.Constructor _ ctorFQName ->
                    if ctorPatternFQName == ctorFQName then
                        let
                            patternLength =
                                List.length argPatterns

                            valueLength =
                                List.length argValues
                        in
                        if patternLength == valueLength then
                            List.map2 evaluatePattern argPatterns argValues
                                |> ListOfResults.liftAllErrors
                                |> Result.mapError ConstructorMismatch
                                |> Result.map (List.foldl Dict.union Dict.empty)

                        else
                            Err (ConstructorArgCountMismatch patternLength valueLength)

                    else
                        Err (ConstructorNameMismatch ctorPatternFQName ctorFQName)

                _ ->
                    Err (ConstructorExpected value)

        Value.EmptyListPattern _ ->
            case value of
                Value.List _ [] ->
                    Ok Dict.empty

                _ ->
                    Err (EmptyListExpected value)

        Value.HeadTailPattern _ headPattern tailPattern ->
            case value of
                Value.List a (headValue :: tailValue) ->
                    Result.map2 Dict.union
                        (evaluatePattern headPattern headValue)
                        (evaluatePattern tailPattern (Value.List a tailValue))

                _ ->
                    Err (NonEmptyListExpected value)

        Value.LiteralPattern _ matchLiteral ->
            case value of
                Value.Literal _ valueLiteral ->
                    if matchLiteral == valueLiteral then
                        Ok Dict.empty

                    else
                        Err (LiteralMismatch matchLiteral valueLiteral)

                _ ->
                    Err (LiteralExpected value)

        Value.UnitPattern _ ->
            case value of
                Value.Unit _ ->
                    Ok Dict.empty

                _ ->
                    Err (UnitExpected value)
