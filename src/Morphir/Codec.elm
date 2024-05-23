module Morphir.Codec exposing (..)

import Json.Decode as Decode
import Json.Encode as Encode


encodeUnit : () -> Encode.Value
encodeUnit () =
    Encode.object []


decodeUnit : Decode.Decoder ()
decodeUnit =
    Decode.succeed ()
