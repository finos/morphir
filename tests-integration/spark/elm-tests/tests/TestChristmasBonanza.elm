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


module TestChristmasBonanza exposing (..)

import AntiqueCsvEncoder exposing (antiqueEncoder)
import AntiquesDataSource exposing (antiquesDataSource)
import Csv.Decode as Decode exposing (..)
import Expect exposing (Expectation)
import SparkTests.DataDefinition.Persistence.Income.AntiqueShop exposing (Antique, Product(..))
import SparkTests.Rules.Income.Antique exposing (..)
import Test exposing (..)


testChristmasBonanza : Test
testChristmasBonanza =
    let
        priceRange : Result Error PriceRange
        priceRange =
            antiquesDataSource
                |> Result.map
                    (\itemsList ->
                        christmas_bonanza_15percent_priceRange itemsList
                    )

        _ =
            Debug.log "antiques_expected_results_christmas_bonanza_15percent_priceRange.csv" priceRange
    in
    test "Testing christmas_bonanza_15percent_priceRange antique shop rule" (\_ -> Expect.equal priceRange (( 0.0, 150000.0 ) |> Ok))
