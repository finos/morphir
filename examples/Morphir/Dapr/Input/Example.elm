module Morphir.Dapr.Input.Example exposing (..)

import Morphir.SDK.StatefulApp exposing (StatefulApp)


type alias ID =
    String


type alias ProductID =
    String


type alias Price =
    Float


type alias Quantity =
    Int


type alias Deal =
    { id : ID
    , product : ProductID
    , price : Price
    , quantity : Quantity
    }


type DealCmd
    = OpenDeal ID ProductID Price Quantity
    | CloseDeal ID


type DealEvent
    = DealOpened ID ProductID Price Quantity
    | DealClosed ID
    | InvalidQuantity ID Quantity
    | InvalidPrice ID Price
    | DuplicateDeal ID
    | DealNotFound ID


type alias App =
    StatefulApp ID DealCmd Deal DealEvent


app : App
app =
    StatefulApp logic


logic : ID -> Maybe Deal -> DealCmd -> ( String, Maybe Deal, DealEvent )
logic dealId deal dealCmd =
    case deal of
        Just d ->
            case dealCmd of
                CloseDeal _ ->
                    ( dealId, Nothing, DealClosed dealId )

                OpenDeal _ _ _ _ ->
                    ( dealId, deal, DuplicateDeal dealId )

        Nothing ->
            case dealCmd of
                OpenDeal id productId price qty ->
                    if price < 0 then
                        ( dealId, deal, InvalidPrice id price )

                    else if qty < 0 then
                        ( dealId, deal, InvalidQuantity id qty )

                    else
                        ( dealId
                        , Deal id productId price qty |> Just
                        , DealOpened id productId price qty
                        )

                CloseDeal _ ->
                    ( dealId, deal, DealNotFound dealId )
