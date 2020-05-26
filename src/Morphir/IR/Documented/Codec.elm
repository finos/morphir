module Morphir.IR.Documented.Codec exposing (..)

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.Documented exposing (Documented)


encodeDocumented : (a -> Encode.Value) -> Documented a -> Encode.Value
encodeDocumented encodeValue d =
    Encode.list identity
        [ Encode.string d.doc
        , encodeValue d.value
        ]


decodeDocumented : Decode.Decoder a -> Decode.Decoder (Documented a)
decodeDocumented decodeValue =
    Decode.map2 Documented
        (Decode.index 1 Decode.string)
        (Decode.index 2 decodeValue)
