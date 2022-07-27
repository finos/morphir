{-
   Copyright 2022 Morgan Stanley

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


module AntiqueCsvDecoder exposing (antiqueDecoder)

import Csv.Decode as Decode exposing (..)
import SparkTests.DataDefinition.Field.Category exposing (Category(..))
import SparkTests.DataDefinition.Field.Report exposing (FeedBack(..))
import SparkTests.DataDefinition.Persistence.Income.AntiqueShop exposing (Antique, Product(..))
import SparkTests.Rules.Income.Antique exposing (..)


productFromString : String -> Result String Product
productFromString str =
    if String.isEmpty str then
        Err "Empty strings are not valid Antique Product strings."

    else
        case str of
            "Paintings" ->
                Paintings |> Ok

            "Knife" ->
                Knife |> Ok

            "Plates" ->
                Plates |> Ok

            "Furniture" ->
                Furniture |> Ok

            "HistoryWritings" ->
                HistoryWritings |> Ok

            _ ->
                Err "Invalid Antique Product string."


toProduct : Decoder Product
toProduct =
    andThen
        (\value -> fromResult (productFromString value))
        Decode.string


categoryFromString : String -> Result String Category
categoryFromString str =
    if String.isEmpty str then
        Err "Empty strings are not valid Antique Category strings."

    else
        case str of
            "PaintCollections" ->
                PaintCollections |> Ok

            "HouseHoldCollection" ->
                HouseHoldCollection |> Ok

            "SimpleToolCollection" ->
                SimpleToolCollection |> Ok

            "Diary" ->
                Diary |> Ok

            _ ->
                Err "Invalid Antique Category string."


toCategory : Decoder Category
toCategory =
    andThen
        (\value -> fromResult (categoryFromString value))
        Decode.string


feedBackFromString : String -> Result String FeedBack
feedBackFromString str =
    if String.isEmpty str then
        Err "Empty strings are not valid FeedBack strings."

    else
        case str of
            "Genuine" ->
                Genuine |> Ok

            "Fake" ->
                Fake |> Ok

            _ ->
                Err "Invalid FeedBack string."


toFeedBack : Decoder FeedBack
toFeedBack =
    andThen
        (\value -> fromResult (feedBackFromString value))
        Decode.string


boolFromString : String -> Result String Bool
boolFromString str =
    if String.isEmpty str then
        Err "Empty strings are not valid Boolean strings."

    else
        case str of
            "True" ->
                True |> Ok

            "False" ->
                False |> Ok

            _ ->
                Err "Invalid Boolean string."


toBool : Decoder Bool
toBool =
    andThen
        (\value -> fromResult (boolFromString value))
        Decode.string


antiqueDecoder : Decoder Antique
antiqueDecoder =
    Decode.into Antique
        |> Decode.pipeline (Decode.field "category" (Decode.blank toCategory))
        |> Decode.pipeline (Decode.field "product" toProduct)
        |> Decode.pipeline (Decode.field "priceValue" Decode.float)
        |> Decode.pipeline (Decode.field "ageOfItem" Decode.int)
        |> Decode.pipeline (Decode.field "handMade" toBool)
        |> Decode.pipeline (Decode.field "requiresExpert" toBool)
        |> Decode.pipeline (Decode.field "expertFeedBack" (Decode.blank toFeedBack))
        |> Decode.pipeline (Decode.field "report" (Decode.blank Decode.string))
