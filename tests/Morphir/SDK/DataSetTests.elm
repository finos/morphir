module Morphir.SDK.DataSetTests exposing (aggregateMapTests)

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

import Expect
import Morphir.SDK.DataSet as DataSet exposing (DataSet, aggregateMap, aggregateMap2, aggregateMap3, maximumOf, minimumOf, sumOf)
import Morphir.SDK.Key exposing (key2, noKey)
import Test exposing (..)


type alias TestInput1 =
    { key1 : String
    , key2 : String
    , value : Float
    }


aggregateMapTests : Test
aggregateMapTests =
    let
        testDataSet : DataSet TestInput1
        testDataSet =
            DataSet.fromList
                [ TestInput1 "k1_1" "k2_1" 1
                , TestInput1 "k1_1" "k2_1" 2
                , TestInput1 "k1_1" "k2_2" 3
                , TestInput1 "k1_1" "k2_2" 4
                , TestInput1 "k1_2" "k2_1" 5
                , TestInput1 "k1_2" "k2_1" 6
                , TestInput1 "k1_2" "k2_2" 7
                , TestInput1 "k1_2" "k2_2" 8
                ]
    in
    describe "aggregateMap"
        [ test "aggregate by single key" <|
            \_ ->
                testDataSet
                    |> aggregateMap
                        ( .key1, always True, sumOf .value )
                        (\totalValue input ->
                            ( input, totalValue / input.value )
                        )
                    |> Expect.equal
                        (DataSet.fromList
                            [ ( TestInput1 "k1_1" "k2_1" 1, 10 / 1 )
                            , ( TestInput1 "k1_1" "k2_1" 2, 10 / 2 )
                            , ( TestInput1 "k1_1" "k2_2" 3, 10 / 3 )
                            , ( TestInput1 "k1_1" "k2_2" 4, 10 / 4 )
                            , ( TestInput1 "k1_2" "k2_1" 5, 26 / 5 )
                            , ( TestInput1 "k1_2" "k2_1" 6, 26 / 6 )
                            , ( TestInput1 "k1_2" "k2_2" 7, 26 / 7 )
                            , ( TestInput1 "k1_2" "k2_2" 8, 26 / 8 )
                            ]
                        )
        , test "aggregate by composite key" <|
            \_ ->
                testDataSet
                    |> aggregateMap
                        ( key2 .key1 .key2, always True, sumOf .value )
                        (\totalValue input ->
                            ( input, totalValue / input.value )
                        )
                    |> Expect.equal
                        (DataSet.fromList
                            [ ( TestInput1 "k1_1" "k2_1" 1, 3 / 1 )
                            , ( TestInput1 "k1_1" "k2_1" 2, 3 / 2 )
                            , ( TestInput1 "k1_1" "k2_2" 3, 7 / 3 )
                            , ( TestInput1 "k1_1" "k2_2" 4, 7 / 4 )
                            , ( TestInput1 "k1_2" "k2_1" 5, 11 / 5 )
                            , ( TestInput1 "k1_2" "k2_1" 6, 11 / 6 )
                            , ( TestInput1 "k1_2" "k2_2" 7, 15 / 7 )
                            , ( TestInput1 "k1_2" "k2_2" 8, 15 / 8 )
                            ]
                        )
        , test "aggregate by no key" <|
            \_ ->
                testDataSet
                    |> aggregateMap
                        ( noKey, \a -> a.value > 3, sumOf .value )
                        (\totalValue input ->
                            ( input, totalValue / input.value )
                        )
                    |> Expect.equal
                        (DataSet.fromList
                            [ ( TestInput1 "k1_1" "k2_1" 1, 30 / 1 )
                            , ( TestInput1 "k1_1" "k2_1" 2, 30 / 2 )
                            , ( TestInput1 "k1_1" "k2_2" 3, 30 / 3 )
                            , ( TestInput1 "k1_1" "k2_2" 4, 30 / 4 )
                            , ( TestInput1 "k1_2" "k2_1" 5, 30 / 5 )
                            , ( TestInput1 "k1_2" "k2_1" 6, 30 / 6 )
                            , ( TestInput1 "k1_2" "k2_2" 7, 30 / 7 )
                            , ( TestInput1 "k1_2" "k2_2" 8, 30 / 8 )
                            ]
                        )
        , test "aggregate 2" <|
            \_ ->
                testDataSet
                    |> aggregateMap2
                        ( .key1, always True, sumOf .value )
                        ( .key2, always True, maximumOf .value )
                        (\totalValue maxValue input ->
                            ( input, totalValue * maxValue / input.value )
                        )
                    |> Expect.equal
                        (DataSet.fromList
                            [ ( TestInput1 "k1_1" "k2_1" 1, 10 * 6 / 1 )
                            , ( TestInput1 "k1_1" "k2_1" 2, 10 * 6 / 2 )
                            , ( TestInput1 "k1_1" "k2_2" 3, 10 * 8 / 3 )
                            , ( TestInput1 "k1_1" "k2_2" 4, 10 * 8 / 4 )
                            , ( TestInput1 "k1_2" "k2_1" 5, 26 * 6 / 5 )
                            , ( TestInput1 "k1_2" "k2_1" 6, 26 * 6 / 6 )
                            , ( TestInput1 "k1_2" "k2_2" 7, 26 * 8 / 7 )
                            , ( TestInput1 "k1_2" "k2_2" 8, 26 * 8 / 8 )
                            ]
                        )
        , test "aggregate 3" <|
            \_ ->
                testDataSet
                    |> aggregateMap3
                        ( .key1, always True, sumOf .value )
                        ( .key2, always True, maximumOf .value )
                        ( key2 .key1 .key2, always True, minimumOf .value )
                        (\totalValue maxValue minValue input ->
                            ( input, totalValue * maxValue / input.value + minValue )
                        )
                    |> Expect.equal
                        (DataSet.fromList
                            [ ( TestInput1 "k1_1" "k2_1" 1, 10 * 6 / 1 + 1 )
                            , ( TestInput1 "k1_1" "k2_1" 2, 10 * 6 / 2 + 1 )
                            , ( TestInput1 "k1_1" "k2_2" 3, 10 * 8 / 3 + 3 )
                            , ( TestInput1 "k1_1" "k2_2" 4, 10 * 8 / 4 + 3 )
                            , ( TestInput1 "k1_2" "k2_1" 5, 26 * 6 / 5 + 5 )
                            , ( TestInput1 "k1_2" "k2_1" 6, 26 * 6 / 6 + 5 )
                            , ( TestInput1 "k1_2" "k2_2" 7, 26 * 8 / 7 + 7 )
                            , ( TestInput1 "k1_2" "k2_2" 8, 26 * 8 / 8 + 7 )
                            ]
                        )
        ]
