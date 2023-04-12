module Morphir.Cadl.Backend.Codec exposing (..)

import Json.Encode as Encode
import Morphir.Cadl.Backend exposing (Errors)


encodeErrors : Errors -> Encode.Value
encodeErrors =
    Encode.list Encode.string
