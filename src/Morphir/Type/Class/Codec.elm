module Morphir.Type.Class.Codec exposing (..)

import Json.Encode as Encode
import Morphir.Type.Class exposing (Class(..))


encodeClass : Class -> Encode.Value
encodeClass class =
    case class of
        Number ->
            Encode.list identity
                [ Encode.string "Number"
                ]

        Appendable ->
            Encode.list identity
                [ Encode.string "Appendable"
                ]
