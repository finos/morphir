module Morphir.Scala.Backend.Codec exposing (..)

import Json.Decode as Decode
import Morphir.Scala.Backend exposing (Options)


decodeOptions : Decode.Decoder Options
decodeOptions =
    Decode.map Options
        (Decode.field "targetPackage" (Decode.list Decode.string))
