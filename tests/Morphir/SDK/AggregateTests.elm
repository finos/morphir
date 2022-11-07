module Morphir.SDK.AggregateTests exposing (aggregateMapTests)

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
import Morphir.SDK.Aggregate exposing (aggregateMap, aggregateMap2, aggregateMap3, aggregateMap4, averageOf, byKey, count, maximumOf, minimumOf, sumOf, weightedAverageOf, withFilter)
import Morphir.SDK.Key exposing (key2, key3, noKey)
import Test exposing (..)


type alias TestInput1 =
    { key1 : String
    , key2 : String
    , value : Float
    }


aggregateMapTests : Test
aggregateMapTests =
    let
        testDataSet : List TestInput1
        testDataSet =
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
                        (sumOf .value |> byKey .key1)
                        (\totalValue input ->
                            ( input, totalValue / input.value )
                        )
                    |> Expect.equal
                        [ ( TestInput1 "k1_1" "k2_1" 1, 10 / 1 )
                        , ( TestInput1 "k1_1" "k2_1" 2, 10 / 2 )
                        , ( TestInput1 "k1_1" "k2_2" 3, 10 / 3 )
                        , ( TestInput1 "k1_1" "k2_2" 4, 10 / 4 )
                        , ( TestInput1 "k1_2" "k2_1" 5, 26 / 5 )
                        , ( TestInput1 "k1_2" "k2_1" 6, 26 / 6 )
                        , ( TestInput1 "k1_2" "k2_2" 7, 26 / 7 )
                        , ( TestInput1 "k1_2" "k2_2" 8, 26 / 8 )
                        ]
        , test "aggregate by composite key" <|
            \_ ->
                testDataSet
                    |> aggregateMap
                        (sumOf .value |> byKey (key2 .key1 .key2))
                        (\totalValue input ->
                            ( input, totalValue / input.value )
                        )
                    |> Expect.equal
                        [ ( TestInput1 "k1_1" "k2_1" 1, 3 / 1 )
                        , ( TestInput1 "k1_1" "k2_1" 2, 3 / 2 )
                        , ( TestInput1 "k1_1" "k2_2" 3, 7 / 3 )
                        , ( TestInput1 "k1_1" "k2_2" 4, 7 / 4 )
                        , ( TestInput1 "k1_2" "k2_1" 5, 11 / 5 )
                        , ( TestInput1 "k1_2" "k2_1" 6, 11 / 6 )
                        , ( TestInput1 "k1_2" "k2_2" 7, 15 / 7 )
                        , ( TestInput1 "k1_2" "k2_2" 8, 15 / 8 )
                        ]
        , test "aggregate by no key and filter" <|
            \_ ->
                testDataSet
                    |> aggregateMap
                        (sumOf .value |> withFilter (\a -> a.value > 3))
                        (\totalValue input ->
                            ( input, totalValue / input.value )
                        )
                    |> Expect.equal
                        [ ( TestInput1 "k1_1" "k2_1" 1, 30 / 1 )
                        , ( TestInput1 "k1_1" "k2_1" 2, 30 / 2 )
                        , ( TestInput1 "k1_1" "k2_2" 3, 30 / 3 )
                        , ( TestInput1 "k1_1" "k2_2" 4, 30 / 4 )
                        , ( TestInput1 "k1_2" "k2_1" 5, 30 / 5 )
                        , ( TestInput1 "k1_2" "k2_1" 6, 30 / 6 )
                        , ( TestInput1 "k1_2" "k2_2" 7, 30 / 7 )
                        , ( TestInput1 "k1_2" "k2_2" 8, 30 / 8 )
                        ]
        , test "aggregate 2" <|
            \_ ->
                testDataSet
                    |> aggregateMap2
                        (sumOf .value |> byKey .key1)
                        (maximumOf .value |> byKey .key2)
                        (\totalValue maxValue input ->
                            ( input, totalValue * maxValue / input.value )
                        )
                    |> Expect.equal
                        [ ( TestInput1 "k1_1" "k2_1" 1, 10 * 6 / 1 )
                        , ( TestInput1 "k1_1" "k2_1" 2, 10 * 6 / 2 )
                        , ( TestInput1 "k1_1" "k2_2" 3, 10 * 8 / 3 )
                        , ( TestInput1 "k1_1" "k2_2" 4, 10 * 8 / 4 )
                        , ( TestInput1 "k1_2" "k2_1" 5, 26 * 6 / 5 )
                        , ( TestInput1 "k1_2" "k2_1" 6, 26 * 6 / 6 )
                        , ( TestInput1 "k1_2" "k2_2" 7, 26 * 8 / 7 )
                        , ( TestInput1 "k1_2" "k2_2" 8, 26 * 8 / 8 )
                        ]
        , test "aggregate 3" <|
            \_ ->
                testDataSet
                    |> aggregateMap3
                        (sumOf .value |> byKey .key1)
                        (maximumOf .value |> byKey .key2)
                        (minimumOf .value |> byKey (key2 .key1 .key2))
                        (\totalValue maxValue minValue input ->
                            ( input, totalValue * maxValue / input.value + minValue )
                        )
                    |> Expect.equal
                        [ ( TestInput1 "k1_1" "k2_1" 1, 10 * 6 / 1 + 1 )
                        , ( TestInput1 "k1_1" "k2_1" 2, 10 * 6 / 2 + 1 )
                        , ( TestInput1 "k1_1" "k2_2" 3, 10 * 8 / 3 + 3 )
                        , ( TestInput1 "k1_1" "k2_2" 4, 10 * 8 / 4 + 3 )
                        , ( TestInput1 "k1_2" "k2_1" 5, 26 * 6 / 5 + 5 )
                        , ( TestInput1 "k1_2" "k2_1" 6, 26 * 6 / 6 + 5 )
                        , ( TestInput1 "k1_2" "k2_2" 7, 26 * 8 / 7 + 7 )
                        , ( TestInput1 "k1_2" "k2_2" 8, 26 * 8 / 8 + 7 )
                        ]
        , test "aggregate 4" <|
            \_ ->
                testDataSet
                    |> aggregateMap4
                        (sumOf .value |> byKey .key1)
                        (maximumOf .value |> byKey .key2)
                        (minimumOf .value |> byKey (key2 .key1 .key2))
                        (averageOf .value |> byKey (key2 .key1 .key2))
                        (\totalValue maxValue minValue average input ->
                            ( input, totalValue * maxValue / input.value + minValue + average )
                        )
                    |> Expect.equal
                        [ ( TestInput1 "k1_1" "k2_1" 1, 10 * 6 / 1 + 1 + 1.5 )
                        , ( TestInput1 "k1_1" "k2_1" 2, 10 * 6 / 2 + 1 + 1.5 )
                        , ( TestInput1 "k1_1" "k2_2" 3, 10 * 8 / 3 + 3 + 3.5 )
                        , ( TestInput1 "k1_1" "k2_2" 4, 10 * 8 / 4 + 3 + 3.5 )
                        , ( TestInput1 "k1_2" "k2_1" 5, 26 * 6 / 5 + 5 + 5.5 )
                        , ( TestInput1 "k1_2" "k2_1" 6, 26 * 6 / 6 + 5 + 5.5 )
                        , ( TestInput1 "k1_2" "k2_2" 7, 26 * 8 / 7 + 7 + 7.5 )
                        , ( TestInput1 "k1_2" "k2_2" 8, 26 * 8 / 8 + 7 + 7.5 )
                        ]
        , test "count by single key" <|
            \_ ->
                testDataSet
                    |> aggregateMap
                        (count |> byKey .key1)
                        (\totalValue input ->
                            ( input, totalValue )
                        )
                    |> Expect.equal
                        [ ( TestInput1 "k1_1" "k2_1" 1, 4 )
                        , ( TestInput1 "k1_1" "k2_1" 2, 4 )
                        , ( TestInput1 "k1_1" "k2_2" 3, 4 )
                        , ( TestInput1 "k1_1" "k2_2" 4, 4 )
                        , ( TestInput1 "k1_2" "k2_1" 5, 4 )
                        , ( TestInput1 "k1_2" "k2_1" 6, 4 )
                        , ( TestInput1 "k1_2" "k2_2" 7, 4 )
                        , ( TestInput1 "k1_2" "k2_2" 8, 4 )
                        ]
        , test "sum by single key" <|
            \_ ->
                testDataSet
                    |> aggregateMap
                        (sumOf .value |> byKey .key1)
                        (\totalValue input ->
                            ( input, totalValue )
                        )
                    |> Expect.equal
                        [ ( TestInput1 "k1_1" "k2_1" 1, 10 )
                        , ( TestInput1 "k1_1" "k2_1" 2, 10 )
                        , ( TestInput1 "k1_1" "k2_2" 3, 10 )
                        , ( TestInput1 "k1_1" "k2_2" 4, 10 )
                        , ( TestInput1 "k1_2" "k2_1" 5, 26 )
                        , ( TestInput1 "k1_2" "k2_1" 6, 26 )
                        , ( TestInput1 "k1_2" "k2_2" 7, 26 )
                        , ( TestInput1 "k1_2" "k2_2" 8, 26 )
                        ]
        , test "avg by single key" <|
            \_ ->
                testDataSet
                    |> aggregateMap
                        (averageOf .value |> byKey .key1)
                        (\totalValue input ->
                            ( input, totalValue )
                        )
                    |> Expect.equal
                        [ ( TestInput1 "k1_1" "k2_1" 1, 2.5 )
                        , ( TestInput1 "k1_1" "k2_1" 2, 2.5 )
                        , ( TestInput1 "k1_1" "k2_2" 3, 2.5 )
                        , ( TestInput1 "k1_1" "k2_2" 4, 2.5 )
                        , ( TestInput1 "k1_2" "k2_1" 5, 6.5 )
                        , ( TestInput1 "k1_2" "k2_1" 6, 6.5 )
                        , ( TestInput1 "k1_2" "k2_2" 7, 6.5 )
                        , ( TestInput1 "k1_2" "k2_2" 8, 6.5 )
                        ]
        , test "min by single key" <|
            \_ ->
                testDataSet
                    |> aggregateMap
                        (minimumOf .value |> byKey .key1)
                        (\totalValue input ->
                            ( input, totalValue )
                        )
                    |> Expect.equal
                        [ ( TestInput1 "k1_1" "k2_1" 1, 1 )
                        , ( TestInput1 "k1_1" "k2_1" 2, 1 )
                        , ( TestInput1 "k1_1" "k2_2" 3, 1 )
                        , ( TestInput1 "k1_1" "k2_2" 4, 1 )
                        , ( TestInput1 "k1_2" "k2_1" 5, 5 )
                        , ( TestInput1 "k1_2" "k2_1" 6, 5 )
                        , ( TestInput1 "k1_2" "k2_2" 7, 5 )
                        , ( TestInput1 "k1_2" "k2_2" 8, 5 )
                        ]
        , test "max by single key" <|
            \_ ->
                testDataSet
                    |> aggregateMap
                        (maximumOf .value |> byKey .key1)
                        (\totalValue input ->
                            ( input, totalValue )
                        )
                    |> Expect.equal
                        [ ( TestInput1 "k1_1" "k2_1" 1, 4 )
                        , ( TestInput1 "k1_1" "k2_1" 2, 4 )
                        , ( TestInput1 "k1_1" "k2_2" 3, 4 )
                        , ( TestInput1 "k1_1" "k2_2" 4, 4 )
                        , ( TestInput1 "k1_2" "k2_1" 5, 8 )
                        , ( TestInput1 "k1_2" "k2_1" 6, 8 )
                        , ( TestInput1 "k1_2" "k2_2" 7, 8 )
                        , ( TestInput1 "k1_2" "k2_2" 8, 8 )
                        ]
        , test "weighted average by single key" <|
            \_ ->
                testDataSet
                    |> aggregateMap
                        (weightedAverageOf .value .value |> byKey .key1)
                        (\totalValue input ->
                            ( input, totalValue )
                        )
                    |> Expect.equal
                        [ ( TestInput1 "k1_1" "k2_1" 1, 3 )
                        , ( TestInput1 "k1_1" "k2_1" 2, 3 )
                        , ( TestInput1 "k1_1" "k2_2" 3, 3 )
                        , ( TestInput1 "k1_1" "k2_2" 4, 3 )
                        , ( TestInput1 "k1_2" "k2_1" 5, 174 / 26 )
                        , ( TestInput1 "k1_2" "k2_1" 6, 174 / 26 )
                        , ( TestInput1 "k1_2" "k2_2" 7, 174 / 26 )
                        , ( TestInput1 "k1_2" "k2_2" 8, 174 / 26 )
                        ]
        ]
