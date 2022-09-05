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


module CsvUtils exposing (..)

import Csv.Decode as Decode exposing (..)
import Csv.Encode as Encode exposing (..)

import SparkTests.DataDefinition.Field.Category exposing (Category(..), categoryFromString, categoryToString)
import SparkTests.DataDefinition.Field.Report exposing (FeedBack(..), feedBackToString, feedBackFromString)
import SparkTests.DataDefinition.Persistence.Income.AntiqueShop exposing (Antique, Product(..), productFromString, productToString)


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


boolToString : Bool -> String
boolToString bool =
    case bool of
        True ->
            "True"

        False ->
            "False"


decodeProduct : Decoder Product
decodeProduct =
    andThen
        (\value -> fromResult (productFromString value))
        Decode.string


decodeCategory : Decoder Category
decodeCategory =
    Decode.string
        |> andThen (\value -> fromResult (categoryFromString value))


decodeFeedBack : Decoder FeedBack
decodeFeedBack =
    Decode.string
        |> andThen (\value -> fromResult (feedBackFromString value))


decodeBool : Decoder Bool
decodeBool =
    Decode.string
        |> andThen (\value -> fromResult (boolFromString value))


antiqueDecoder : Decoder Antique
antiqueDecoder =
    Decode.into Antique
        |> Decode.pipeline (Decode.field "category" (Decode.blank decodeCategory))
        |> Decode.pipeline (Decode.field "product" decodeProduct)
        |> Decode.pipeline (Decode.field "priceValue" Decode.float)
        |> Decode.pipeline (Decode.field "ageOfItem" Decode.float)
        |> Decode.pipeline (Decode.field "handMade" decodeBool)
        |> Decode.pipeline (Decode.field "requiresExpert" decodeBool)
        |> Decode.pipeline (Decode.field "expertFeedBack" (Decode.blank decodeFeedBack))
        |> Decode.pipeline (Decode.field "report" (Decode.blank Decode.string))


antiqueEncoder : List Antique -> String
antiqueEncoder antiques =
    antiques
        |> Encode.encode
            { encoder =
                Encode.withFieldNames
                    (\antique ->
                        [ ( "category", categoryToString antique.category )
                        , ( "product", productToString antique.product )
                        , ( "priceValue", String.fromFloat antique.priceValue )
                        , ( "ageOfItem", String.fromFloat antique.ageOfItem )
                        , ( "handMade", boolToString antique.handMade )
                        , ( "requiresExpert", boolToString antique.requiresExpert )
                        , ( "expertFeedback", feedBackToString antique.expertFeedback )
                        , ( "report", antique.report |> Maybe.withDefault "" )
                        ]
                    )
            , fieldSeparator = ','
            }
