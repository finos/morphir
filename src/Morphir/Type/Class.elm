module Morphir.Type.Class exposing (..)

import Morphir.Type.MetaType as MetaType exposing (MetaType)


type Class
    = Number


member : MetaType -> Class -> Bool
member metaType class =
    case class of
        Number ->
            numberTypes
                |> List.member metaType


numberTypes : List MetaType
numberTypes =
    [ MetaType.intType, MetaType.floatType ]
