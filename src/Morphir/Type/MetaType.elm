module Morphir.Type.MetaType exposing (..)

import Morphir.IR.FQName exposing (FQName, fqn)
import Morphir.Type.MetaVar exposing (Variable)


type MetaType
    = MetaVar Variable
    | MetaRef FQName
    | MetaTuple (List MetaType)
    | MetaApply MetaType MetaType
    | MetaFun MetaType MetaType


substituteVariable : Variable -> MetaType -> MetaType -> MetaType
substituteVariable var replacement original =
    case original of
        MetaVar thisVar ->
            if thisVar == var then
                replacement

            else
                original

        MetaTuple metaElems ->
            MetaTuple (metaElems |> List.map (substituteVariable var replacement))

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
