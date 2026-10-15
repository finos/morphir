module Morphir.Example.App.Rentals exposing (..)

import Morphir.Example.App.Analytics exposing (..)
import Morphir.Example.App.BusinessTerms exposing (..)
import Morphir.Example.App.Forecast exposing (..)
import Morphir.Example.App.Winds exposing (..)


type Reason
    = InsufficientAvailability
    | ClosedDueToConditions


decide : WindCategory -> ForecastDetail -> CurrentInventory -> ProbableReservations -> PendingReturns -> RequestedQuantity -> AllowPartials -> Result Reason ReservedQuantity
decide windCategory forecastDetail inventory probableReservations returns requestedQuantity allowPartials =
    let
        isClosed : Bool
        isClosed =
            case ( windCategory, forecastDetail ) of
                ( DangerousWinds, _ ) ->
                    True

                ( _, Thunderstorms ) ->
                    True

                _ ->
                    False

        availability : Availability
        availability =
            inventory - probableReservations + returns
    in
    if isClosed then
        Err ClosedDueToConditions

    else if requestedQuantity <= availability then
        Ok requestedQuantity

    else if allowPartials then
        Ok availability

    else
        Err InsufficientAvailability
