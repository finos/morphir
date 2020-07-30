module Morphir.Scala.Backend.Codec exposing (..)

import Json.Decode as Decode
import Morphir.Scala.Backend exposing (Options)


decodeOptions : Decode.Decoder Options
decodeOptions =
    Decode.succeed Options
