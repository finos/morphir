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


module TestSeizeItem exposing (..)

import AntiqueCsvEncoder exposing (antiqueEncoder)
import AntiquesDataSource exposing (antiquesDataSource)
import Csv.Decode as Decode exposing (..)
import Expect exposing (Expectation)
import SparkTests.DataDefinition.Persistence.Income.AntiqueShop exposing (Antique, Product(..))
import SparkTests.Rules.Income.Antique exposing (..)
import Test exposing (..)


testSeizeItem : Test
testSeizeItem =
    let
        matchingAntiques : Result Error (List Antique)
        matchingAntiques =
            antiquesDataSource
                |> Result.map
                    (\itemsList ->
                        itemsList
                            |> List.filter
                                (\item ->
                                    seize_item item
                                )
                    )

        csvResults =
            matchingAntiques
                |> Result.map
                    (\result ->
                        result |> antiqueEncoder
                    )

        _ =
            Debug.log "antiques_expected_results_seize_item.csv" csvResults
    in
    test "Testing seize_item antique shop rule" (\_ -> Expect.equal (matchingAntiques |> Result.map (\list -> List.length list)) (12200 |> Ok))
