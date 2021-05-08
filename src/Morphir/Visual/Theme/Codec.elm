module Morphir.Visual.Theme.Codec exposing (..)

import Json.Decode as Decode exposing (Decoder)
import Morphir.Visual.Theme exposing (ThemeConfig)


decodeThemeConfig : Decoder ThemeConfig
decodeThemeConfig =
    Decode.map2 ThemeConfig (Decode.field "fontSize" Decode.int |> Decode.maybe) (Decode.field "decimalDigit" Decode.int |> Decode.maybe)
