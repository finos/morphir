{-
Copyright 2020 Morgan Stanley

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}


module Morphir.Dapr.Input.Example exposing (..)

import Morphir.SDK.StatefulApp exposing (StatefulApp)

{- Type aliases for modeling in the language of the business -}

type alias ID =
    String


type alias ProductID =
    String


type alias Price =
    Float


type alias Quantity =
    Int

{- Identifies a structure that can be associated to a persistance entity -}
type alias Deal =
    { id : ID
    , product : ProductID
    , price : Price
    , quantity : Quantity
    }

{- These define the requests that can be made of this service -}
type DealCmd
    = OpenDeal ID ProductID Price Quantity
    | CloseDeal ID

{- These define the responses that would result from requests -}
type DealEvent
    = DealOpened ID ProductID Price Quantity
    | DealClosed ID
    | InvalidQuantity ID Quantity
    | InvalidPrice ID Price
    | DuplicateDeal ID
    | DealNotFound ID

{- Defines that this is a stateful application that uses ID as the entity key (for possible partioning), 
   accepts requests of type DealCmd,
   manages data in the form of a Deal,
   and produces events of type DealEvent.
   
   Note that there's no indication of whether the API is synchronous or asynchronous.  That's up to the implementation to decide.
-}
type alias App =
    StatefulApp ID DealCmd Deal DealEvent


app : App
app =
    StatefulApp logic


{- Defines the business logic of this app. 
   That is whether or not to accept a request to open or close a deal. 
-}
logic : ID -> Maybe Deal -> DealCmd -> ( ID, Maybe Deal, DealEvent )
logic dealId deal dealCmd =
    -- Act accordingly based on whether the deal already exists.
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
