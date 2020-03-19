module Morphir.Elm.Backend.Codec.Tests.DaprExample exposing (..)

import Morphir.SDK.StatefulApp exposing (..)


type alias App =
    StatefulApp Int Int Int


app : App
app =
    StatefulApp logic


logic : Maybe Int -> Int -> ( Maybe Int, Int )
logic state event =
    case state of
        Just s ->
            ( Just (s + event), s + event )

        Nothing ->
            ( Just event, event )
