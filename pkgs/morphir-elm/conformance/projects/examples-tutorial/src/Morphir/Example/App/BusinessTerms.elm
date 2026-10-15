module Morphir.Example.App.BusinessTerms exposing (..)


type alias RentalID =
    String


type alias CurrentInventory =
    Int


type alias ExistingReservations =
    Int


type alias PendingReturns =
    Int


type alias RequestedQuantity =
    Int


type alias ReservedQuantity =
    Int


type alias ProbableReservations =
    Int


type alias CanceledQuantity =
    Int


type alias CancelationRatio =
    Float


type alias Availability =
    Int


type alias AllowPartials =
    Bool


type ExpertiseLevel
    = Novice
    | Intermediate
    | Expert
