module SlateX.DevBot.Java.Options exposing (..)


import Json.Decode as Decode

type alias Options =
    { indent : Int
    , maxWidth : Int
    }


decodeOptions : Decode.Decoder Options
decodeOptions =
    Decode.map2 Options
        (Decode.field "indent" Decode.int)
        (Decode.field "maxWidth" Decode.int)
