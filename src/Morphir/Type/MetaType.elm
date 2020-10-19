module Morphir.Type.MetaType exposing (..)

import Morphir.IR.FQName exposing (FQName)


type alias Variable =
    ( Int, Int )


newMetaTypeVariable : Int -> Variable
newMetaTypeVariable i =
    ( i, 0 )


subMetaTypeVariable : Int -> Variable -> Variable
subMetaTypeVariable s ( i, _ ) =
    ( i, s )


type MetaType
    = MetaVar Variable
    | MetaRef FQName
    | MetaTuple (List MetaType)
    | MetaApply MetaType MetaType


substitute : Variable -> MetaType -> MetaType -> MetaType
substitute var replacement original =
    case original of
        MetaVar thisVar ->
            if thisVar == var then
                replacement

            else
                original

        MetaTuple metaElems ->
            MetaTuple (metaElems |> List.map (substitute var replacement))

        MetaApply metaFun metaArg ->
            MetaApply
                (substitute var replacement metaFun)
                (substitute var replacement metaArg)

        MetaRef _ ->
            original
