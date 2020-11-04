module Morphir.Type.MetaType exposing (..)

import Dict exposing (Dict)
import Morphir.IR.FQName exposing (FQName, fqn)
import Morphir.IR.Name exposing (Name)


type MetaType
    = MetaVar Variable
    | MetaRef FQName
    | MetaTuple (List MetaType)
    | MetaRecord (Maybe Variable) (Dict Name MetaType)
    | MetaApply MetaType MetaType
    | MetaFun MetaType MetaType
    | MetaUnit


type alias Variable =
    ( Int, Int )


variable : Int -> Variable
variable i =
    ( i, 0 )


subVariable : Variable -> Variable
subVariable ( i, s ) =
    ( i, s + 1 )


toName : Variable -> Name
toName ( i, s ) =
    [ "t", String.fromInt i, String.fromInt s ]


substituteVariable : Variable -> MetaType -> MetaType -> MetaType
substituteVariable var replacement original =
    case original of
        MetaVar thisVar ->
            if thisVar == var then
                replacement

            else
                original

        MetaTuple metaElems ->
            MetaTuple
                (metaElems
                    |> List.map (substituteVariable var replacement)
                )

        MetaRecord extends metaFields ->
            if extends == Just var then
                replacement

            else
                MetaRecord extends
                    (metaFields
                        |> Dict.map
                            (\_ fieldType ->
                                substituteVariable var replacement fieldType
                            )
                    )

        MetaApply metaFun metaArg ->
            MetaApply
                (substituteVariable var replacement metaFun)
                (substituteVariable var replacement metaArg)

        MetaFun metaFun metaArg ->
            MetaFun
                (substituteVariable var replacement metaFun)
                (substituteVariable var replacement metaArg)

        MetaRef _ ->
            original

        MetaUnit ->
            original


substituteVariables : List ( Variable, MetaType ) -> MetaType -> MetaType
substituteVariables replacements original =
    replacements
        |> List.foldl
            (\( var, replacement ) soFar ->
                soFar
                    |> substituteVariable var replacement
            )
            original


boolType : MetaType
boolType =
    MetaRef (fqn "Morphir.SDK" "Basics" "Bool")


charType : MetaType
charType =
    MetaRef (fqn "Morphir.SDK" "Char" "Char")


stringType : MetaType
stringType =
    MetaRef (fqn "Morphir.SDK" "String" "String")


intType : MetaType
intType =
    MetaRef (fqn "Morphir.SDK" "Basics" "Int")


floatType : MetaType
floatType =
    MetaRef (fqn "Morphir.SDK" "Basics" "Float")


listType : MetaType -> MetaType
listType itemType =
    MetaApply (MetaRef (fqn "Morphir.SDK" "List" "List")) itemType
