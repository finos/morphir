module Morphir.Type.Class exposing (..)

import Morphir.Type.MetaType as MetaType exposing (MetaType(..))


type Class
    = Number
    | Appendable


member : MetaType -> Class -> Bool
member metaType class =
    let
        targetType : MetaType -> MetaType
        targetType mt =
            case mt of
                MetaRef _ _ _ (Just t) ->
                    targetType t

                _ ->
                    mt
    in
    case class of
        Number ->
            numberTypes
                |> List.member (targetType metaType)

        Appendable ->
            case targetType metaType of
                MetaRef _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) [] _ ->
                    True

                MetaRef _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) [ _ ] _ ->
                    True

                _ ->
                    False


numberTypes : List MetaType
numberTypes =
    [ MetaType.intType, MetaType.floatType ]


toString : Class -> String
toString class =
    case class of
        Number ->
            "number"

        Appendable ->
            "appendable"
