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


module AntiqueCsvEncoder exposing (antiqueEncoder)

import Csv.Encode as Encode exposing (..)
import SparkTests.DataDefinition.Field.Category exposing (Category(..))
import SparkTests.DataDefinition.Field.Report exposing (FeedBack(..))
import SparkTests.DataDefinition.Persistence.Income.AntiqueShop exposing (Antique, Product(..))
import SparkTests.Rules.Income.Antique exposing (..)


productToString : Product -> String
productToString product =
    case product of
        Paintings ->
            "Paintings"

        Knife ->
            "Knife"

        Plates ->
            "Plates"

        Furniture ->
            "Furniture"

        HistoryWritings ->
            "HistoryWritings"


categoryToString : Maybe Category -> String
categoryToString category =
    category
        |> Maybe.map
            (\cat ->
                case cat of
                    PaintCollections ->
                        "PaintCollections"

                    HouseHoldCollection ->
                        "HouseHoldCollection"

                    SimpleToolCollection ->
                        "SimpleToolCollection"

                    Diary ->
                        "Diary"
            )
        |> Maybe.withDefault ""


feedBackToString : Maybe FeedBack -> String
feedBackToString feedBack =
    feedBack
        |> Maybe.map
            (\fb ->
                case fb of
                    Genuine ->
                        "Genuine"

                    Fake ->
                        "Fake"
            )
        |> Maybe.withDefault ""


boolToString : Bool -> String
boolToString bool =
    case bool of
        True ->
            "True"

        False ->
            "False"


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
                        , ( "ageOfItem", String.fromInt antique.ageOfItem )
                        , ( "handMade", boolToString antique.handMade )
                        , ( "requiresExpert", boolToString antique.requiresExpert )
                        , ( "expertFeedback", feedBackToString antique.expertFeedback )
                        , ( "report", antique.report |> Maybe.withDefault "" )
                        ]
                    )
            , fieldSeparator = ','
            }
