module Morphir.JsonSchema.Backend.Codec exposing (..)

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Morphir.JsonSchema.Backend exposing (Error, Options)


decodeOptions : Decoder Options
decodeOptions =
    Decode.map Options (Decode.field "filename" Decode.string)


encodeError : Error -> Encode.Value
encodeError error =
    Encode.list Encode.string error
