module Morphir.JsonSchema.Backend.Codec exposing (..)

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Morphir.JsonSchema.Backend exposing (Error, Errors, Options)


decodeOptions : Decoder Options
decodeOptions =
    Decode.map Options (Decode.field "filename" Decode.string)


encodeErrors : Errors -> Encode.Value
encodeErrors errors =
    Encode.list Encode.string errors
