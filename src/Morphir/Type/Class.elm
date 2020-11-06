module Morphir.Type.Class exposing (..)

import Morphir.Type.MetaType as MetaType exposing (MetaType(..))


type Class
    = Number


member : MetaType -> Class -> Bool
member metaType class =
    let
        targetType : MetaType -> MetaType
        targetType mt =
            case mt of
                MetaAlias _ t ->
                    targetType t

                _ ->
                    mt
    in
    case class of
        Number ->
            numberTypes
                |> List.member (targetType metaType)


numberTypes : List MetaType
numberTypes =
    [ MetaType.intType, MetaType.floatType ]
