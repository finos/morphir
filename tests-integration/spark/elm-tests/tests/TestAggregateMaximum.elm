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


module TestAggregateMaximum exposing (..)

import AntiquesDataSource exposing (antiquesDataSource)
import Csv.Encode as Encode exposing (..)
import CsvUtils exposing (antiqueEncoder)
import SparkTests.AggregationTests exposing (testAggregateMaximum)
import SparkTests.DataDefinition.Persistence.Income.AntiqueShop exposing (Product(..), productToString)
import Test exposing (Test)
import TestUtils exposing (executeTest)


encodeResult : List { product : Product, maximum : Float } -> String
encodeResult results =
    results
        |> Encode.encode
            { encoder =
                Encode.withFieldNames
                    (\result ->
                        [ ( "product", productToString result.product )
                        , ( "maximum", String.fromFloat result.maximum )
                        ]
                    )
            , fieldSeparator = ','
            }


testAggregate : Test
testAggregate =
    executeTest "testAggregateMaximum" antiquesDataSource testAggregateMaximum encodeResult
