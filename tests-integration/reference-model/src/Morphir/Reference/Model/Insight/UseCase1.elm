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


limitTracking : Float -> Float -> Float -> Float -> Float -> List TrackingAdvantage
limitTracking focalURV focalDRV betDeviationThreshold pointURV pointDRV =
    let
        betRocketVolume : Float
        betRocketVolume =
            focalURV + focalDRV

        interstellarTracking : List TrackingAdvantage
        interstellarTracking =
            if focalURV == 0 || focalDRV == 0 then
                noTrackingAdvantage

            else if betRocketVolume > 0 then
                [ TrackingAdvantage Up "123456789" (negate pointDRV)
                , TrackingAdvantage Down "987654321" (focalDRV * (pointURV / focalURV))
                ]

            else
                [ TrackingAdvantage Up "123456789" (focalDRV * (pointURV / focalURV))
                , TrackingAdvantage Down "987654321" (negate pointDRV)
                ]

        collisionTracking : List TrackingAdvantage
        collisionTracking =
            if betDeviationThreshold == 0 || betDeviationThreshold > 0 && betRocketVolume > 0 || betDeviationThreshold < 0 && betRocketVolume < 0 then
                noTrackingAdvantage

            else if betRocketVolume > 0 then
                if abs betDeviationThreshold < abs betRocketVolume then
                    [ TrackingAdvantage Up "123456789" (abs betDeviationThreshold * (pointURV / focalURV))
                    , TrackingAdvantage Down "987654321" (abs betDeviationThreshold * (pointURV / focalURV))
                    ]

                else
                    [ TrackingAdvantage Up "123456789" (abs betDeviationThreshold * (pointURV / focalURV))
                    , TrackingAdvantage Down "987654321" (abs betDeviationThreshold * (pointURV / focalURV))
                    ]

            else if abs betDeviationThreshold < abs betRocketVolume then
                [ TrackingAdvantage Up "123456789" (abs betDeviationThreshold * (pointURV / focalURV))
                , TrackingAdvantage Down "987654321" (abs betDeviationThreshold * (pointURV / focalURV))
                ]

            else
                [ TrackingAdvantage Up "123456789" (abs betDeviationThreshold * (pointURV / focalURV))
                , TrackingAdvantage Down "987654321" (abs betDeviationThreshold * (pointURV / focalURV))
                ]
    in
    List.append interstellarTracking collisionTracking
