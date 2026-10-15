module Morphir.Example.App.App exposing (..)

import Morphir.Example.App.Analytics exposing (calculateProbableReservations)
import Morphir.Example.App.BusinessTerms exposing (..)
import Morphir.Example.App.Forecast exposing (..)
import Morphir.Example.App.Rentals exposing (..)
import Morphir.Example.App.Winds exposing (..)


processRequest : Forecast -> CurrentInventory -> ExistingReservations -> PendingReturns -> RequestedQuantity -> AllowPartials -> ReservedQuantity -> CanceledQuantity -> Result Reason ReservedQuantity
processRequest forecast inventory reservations returns requestedQuantity allowPartials historicalReservations historicalCancelations =
    let
        windCategory : WindCategory
        windCategory =
            categorizeWindForForecast forecast

        probableReservations : ProbableReservations
        probableReservations =
            calculateProbableReservations historicalReservations historicalCancelations reservations
    in
    decide windCategory forecast.shortForcast inventory probableReservations returns requestedQuantity allowPartials


categorizeWindForForecast : Forecast -> WindCategory
categorizeWindForForecast forecast =
    let
        windCategory : WindCategory
        windCategory =
            categorizeWind forecast.windSpeed.max
    in
    windCategory


type Command
    = Request RentalID RequestedQuantity AllowPartials
    | Pickup RentalID
    | Return RentalID


type Event
    = RequestAccepted RentalID ReservedQuantity
    | RequestRejected RentalID Reason
    | PickupCompleted RentalID
    | ReturnCompleted RentalID


type alias State =
    { forecast : Forecast
    , currentInventory : CurrentInventory
    , events : List Event
    }
