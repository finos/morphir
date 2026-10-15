module Morphir.Example.App.Forecast exposing (..)


type alias MPH =
    Int


type WindDirection
    = North
    | South
    | East
    | West


type alias Celcius =
    Int


type ForecastDetail
    = Showers
    | Thunderstorms
    | Snow
    | Fog


type alias ForecastPercent =
    Float


type alias Forecast =
    { temp : { low : Celcius, high : Celcius }
    , windSpeed : { min : MPH, max : MPH }
    , windDirection : WindDirection
    , shortForcast : ForecastDetail
    , forecastPercent : ForecastPercent
    }
