module Morphir.Example.App.Winds exposing (..)

import Morphir.Example.App.Forecast exposing (..)


type WindCategory
    = Calm
    | Windy
    | HighWinds
    | DangerousWinds


categorizeWind : Int -> WindCategory
categorizeWind windSpeed =
    if windSpeed < 10 then
        Calm

    else if windSpeed < 20 then
        HighWinds

    else if windSpeed < 30 then
        Windy

    else
        DangerousWinds
