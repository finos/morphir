module Morphir.TypeSpec.Backend.Codec exposing (..)

import Json.Encode as Encode
import Morphir.TypeSpec.Backend exposing (Errors)


encodeErrors : Errors -> Encode.Value
encodeErrors =
    Encode.list Encode.string
