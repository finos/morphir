module Morphir.Example.App.Analytics exposing (..)

import Morphir.Example.App.BusinessTerms exposing (..)


calculateProbableReservations : ReservedQuantity -> CanceledQuantity -> ReservedQuantity -> ProbableReservations
calculateProbableReservations averageReservationRequests averageCancelations currentReservationCount =
    let
        probableReservations : ProbableReservations
        probableReservations =
            ceiling (toFloat currentReservationCount * (1.0 - cancelationRatio averageReservationRequests averageCancelations))
    in
    probableReservations



-- Naive


cancelationRatio : ReservedQuantity -> CanceledQuantity -> CancelationRatio
cancelationRatio reservationRequests cancelations =
    let
        result : CancelationRatio
        result =
            toFloat cancelations / toFloat reservationRequests
    in
    result



-- Safe


cancelationRatioSafe : ReservedQuantity -> CanceledQuantity -> Result String CancelationRatio
cancelationRatioSafe reservationRequests cancelations =
    safeRatio cancelations reservationRequests


safeRatio : Int -> Int -> Result String CancelationRatio
safeRatio numerator denominator =
    let
        result : Result String CancelationRatio
        result =
            if numerator < 0 || denominator < 0 then
                Err "Only natural numbers allowed"

            else if numerator > denominator then
                Err "The numerator must be less than or equal to the denominator"

            else if denominator == 0 then
                Ok 0.0

            else
                Ok (toFloat numerator / toFloat denominator)
    in
    result
