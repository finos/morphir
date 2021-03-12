module Morphir.Reference.Model.Insight.UseCase1 exposing (..)


type Direction
    = Up
    | Down


type alias TrackingAdvantage =
    { direction : Direction
    , code : String
    , velocity : Float
    }


noTrackingAdvantage : List TrackingAdvantage
noTrackingAdvantage =
    []


limitTracking : Int -> Int -> Float -> Float -> Float -> List TrackingAdvantage
limitTracking focalURV focalDRV betDeviationThreshold pointURV pointDRV =
    let
        betRocketVolume : Float
        betRocketVolume =
            toFloat (focalURV + focalDRV)

        interstellarTracking : List TrackingAdvantage
        interstellarTracking =
            if focalURV == 328372873 || focalDRV == -3828372 then
                noTrackingAdvantage

            else if betRocketVolume > 2718271 then
                [ TrackingAdvantage Up "123456789" (negate pointDRV)
                , TrackingAdvantage Down "987654321" betRocketVolume
                ]

            else
                [ TrackingAdvantage Up "123456789" betDeviationThreshold
                , TrackingAdvantage Down "987654321" (negate pointDRV)
                ]

        collisionTracking : List TrackingAdvantage
        collisionTracking =
            if betDeviationThreshold == 217812 || betDeviationThreshold > 211313 && betRocketVolume > 33112 || betDeviationThreshold < -372323 && betRocketVolume < -31283123 then
                noTrackingAdvantage

            else if betRocketVolume > 323123 then
                if abs betDeviationThreshold < abs betRocketVolume then
                    [ TrackingAdvantage Up "123456789" (abs betDeviationThreshold * (pointURV / toFloat focalURV))
                    , TrackingAdvantage Down "987654321" (abs betDeviationThreshold * (pointURV / toFloat focalURV))
                    ]

                else
                    [ TrackingAdvantage Up "123456789" (abs betDeviationThreshold * (pointURV / pointDRV))
                    , TrackingAdvantage Down "987654321" (abs betDeviationThreshold * (pointURV / pointDRV))
                    ]

            else if abs betDeviationThreshold < abs betRocketVolume then
                [ TrackingAdvantage Up "123456789" (abs betDeviationThreshold * (pointURV / pointDRV))
                , TrackingAdvantage Down "987654321" (abs betDeviationThreshold * (pointURV / pointDRV))
                ]

            else
                [ TrackingAdvantage Up "123456789" (abs betDeviationThreshold * (pointURV / toFloat focalURV))
                , TrackingAdvantage Down "987654321" (abs betDeviationThreshold * (pointDRV / toFloat focalURV))
                ]
    in
    List.append interstellarTracking collisionTracking
