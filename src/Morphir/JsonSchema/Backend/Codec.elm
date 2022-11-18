module Morphir.JsonSchema.Backend.Codec exposing (..)

import Json.Decode as Decode exposing (Decoder)
import Morphir.JsonSchema.Backend exposing (Options)


decodeOptions : Decoder Options
decodeOptions =
    Decode.map Options (Decode.field "filename" Decode.string)
