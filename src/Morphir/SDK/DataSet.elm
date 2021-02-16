module Morphir.SDK.DataSet exposing
    ( DataSet, fromList, toList
    , aggregateMap, aggregateMap2, aggregateMap3
    , count, sumOf, minimumOf, maximumOf, averageOf, weightedAverageOf
    )

{-| This module contains functions specifically designed to work with large data sets.

@docs DataSet, fromList, toList


# Aggregations

@docs aggregateMap, aggregateMap2, aggregateMap3


## Operators

@docs count, sumOf, minimumOf, maximumOf, averageOf, weightedAverageOf

-}

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

import AssocList as Dict exposing (Dict)


{-| Represents a data set where each row is of type `a`.
-}
type DataSet a
    = DataSet (List a)


type AggregateOp a
    = Count
    | Sum (a -> Float)
    | Avg (a -> Float)
    | Min (a -> Float)
    | Max (a -> Float)
    | WAvg (a -> Float) (a -> Float)


{-| Count the number of rows in a group.
-}
count : AggregateOp a
count =
    Count


{-| Apply a function to each row that returns a numeric value and return the sum of the values.
-}
sumOf : (a -> Float) -> AggregateOp a
sumOf =
    Sum


{-| Apply a function to each row that returns a numeric value and return the average of the values.
-}
averageOf : (a -> Float) -> AggregateOp a
averageOf =
    Avg


{-| Apply a function to each row that returns a numeric value and return the minimum of the values.
-}
minimumOf : (a -> Float) -> AggregateOp a
minimumOf =
    Min


{-| Apply a function to each row that returns a numeric value and return the maximum of the values.
-}
maximumOf : (a -> Float) -> AggregateOp a
maximumOf =
    Max


{-| Apply two functions to each row that returns a numeric value and return the weighted of the values using the first
function to get the weights.
-}
weightedAverageOf : (a -> Float) -> (a -> Float) -> AggregateOp a
weightedAverageOf =
    WAvg


{-| Create a data set from a list.
-}
fromList : List a -> DataSet a
fromList list =
    DataSet list


{-| Turn a data set into a list.
-}
toList : DataSet a -> List a
toList (DataSet list) =
    list


{-| Map function that provides an aggregated value to the mapping function. The first argument is a tuple where the
first element is a function that defines the aggregation key, the second element is predicate that allows you to filter
out certain rows from the aggregation and the third argument is the aggregation operation to apply. Usage:

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

        testDataSet
            |> aggregateMap
                ( .key1, always True, sumOf .value )
                    (\\totalValue input ->
                        ( input, totalValue / input.value )
                    )
            {- ==
                DataSet.fromList
                    [ ( TestInput1 "k1_1" "k2_1" 1, 10 / 1 )
                    , ( TestInput1 "k1_1" "k2_1" 2, 10 / 2 )
                    , ( TestInput1 "k1_1" "k2_2" 3, 10 / 3 )
                    , ( TestInput1 "k1_1" "k2_2" 4, 10 / 4 )
                    , ( TestInput1 "k1_2" "k2_1" 5, 26 / 5 )
                    , ( TestInput1 "k1_2" "k2_1" 6, 26 / 6 )
                    , ( TestInput1 "k1_2" "k2_2" 7, 26 / 7 )
                    , ( TestInput1 "k1_2" "k2_2" 8, 26 / 8 )
                    ]
            -}

-}
aggregateMap : ( a -> key1, a -> Bool, AggregateOp a ) -> (Float -> a -> b) -> DataSet a -> DataSet b
aggregateMap ( key1, predicate1, op1 ) f (DataSet list) =
    let
        aggregated1 : Dict key1 Float
        aggregated1 =
            list
                |> List.filter predicate1
                |> aggregateHelp key1 op1
    in
    list
        |> List.map
            (\a ->
                f (aggregated1 |> Dict.get (key1 a) |> Maybe.withDefault 0) a
            )
        |> DataSet


{-| Map function that provides two aggregated values to the mapping function. The first argument is a tuple where the
first element is a function that defines the aggregation key, the second element is predicate that allows you to filter
out certain rows from the aggregation and the third argument is the aggregation operation to apply. Usage:

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

        testDataSet
            |> aggregateMap2
                ( .key1, always True, sumOf .value )
                ( .key2, always True, maximumOf .value )
                (\totalValue maxValue input ->
                    ( input, totalValue * maxValue / input.value )
                )
            {- ==
                DataSet.fromList
                    [ ( TestInput1 "k1_1" "k2_1" 1, 10 * 6 / 1 )
                    , ( TestInput1 "k1_1" "k2_1" 2, 10 * 6 / 2 )
                    , ( TestInput1 "k1_1" "k2_2" 3, 10 * 8 / 3 )
                    , ( TestInput1 "k1_1" "k2_2" 4, 10 * 8 / 4 )
                    , ( TestInput1 "k1_2" "k2_1" 5, 26 * 6 / 5 )
                    , ( TestInput1 "k1_2" "k2_1" 6, 26 * 6 / 6 )
                    , ( TestInput1 "k1_2" "k2_2" 7, 26 * 8 / 7 )
                    , ( TestInput1 "k1_2" "k2_2" 8, 26 * 8 / 8 )
                    ]
            -}

-}
aggregateMap2 : ( a -> key1, a -> Bool, AggregateOp a ) -> ( a -> key2, a -> Bool, AggregateOp a ) -> (Float -> Float -> a -> b) -> DataSet a -> DataSet b
aggregateMap2 ( key1, predicate1, op1 ) ( key2, predicate2, op2 ) f (DataSet list) =
    let
        aggregated1 : Dict key1 Float
        aggregated1 =
            list
                |> List.filter predicate1
                |> aggregateHelp key1 op1

        aggregated2 : Dict key2 Float
        aggregated2 =
            list
                |> List.filter predicate2
                |> aggregateHelp key2 op2
    in
    list
        |> List.map
            (\a ->
                a
                    |> f
                        (aggregated1 |> Dict.get (key1 a) |> Maybe.withDefault 0)
                        (aggregated2 |> Dict.get (key2 a) |> Maybe.withDefault 0)
            )
        |> DataSet


{-| Map function that provides three aggregated values to the mapping function. The first argument is a tuple where the
first element is a function that defines the aggregation key, the second element is predicate that allows you to filter
out certain rows from the aggregation and the third argument is the aggregation operation to apply. Usage:

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

        testDataSet
            |> aggregateMap3
                ( .key1, always True, sumOf .value )
                ( .key2, always True, maximumOf .value )
                ( key2 .key1 .key2, minimumOf .value )
                (\totalValue maxValue minValue input ->
                    ( input, totalValue * maxValue / input.value + minValue )
                )
            {- ==
                DataSet.fromList
                    [ ( TestInput1 "k1_1" "k2_1" 1, 10 * 6 / 1 + 1 )
                    , ( TestInput1 "k1_1" "k2_1" 2, 10 * 6 / 2 + 1 )
                    , ( TestInput1 "k1_1" "k2_2" 3, 10 * 8 / 3 + 3 )
                    , ( TestInput1 "k1_1" "k2_2" 4, 10 * 8 / 4 + 3 )
                    , ( TestInput1 "k1_2" "k2_1" 5, 26 * 6 / 5 + 5 )
                    , ( TestInput1 "k1_2" "k2_1" 6, 26 * 6 / 6 + 5 )
                    , ( TestInput1 "k1_2" "k2_2" 7, 26 * 8 / 7 + 7 )
                    , ( TestInput1 "k1_2" "k2_2" 8, 26 * 8 / 8 + 7 )
                    ]
            -}

-}
aggregateMap3 : ( a -> key1, a -> Bool, AggregateOp a ) -> ( a -> key2, a -> Bool, AggregateOp a ) -> ( a -> key3, a -> Bool, AggregateOp a ) -> (Float -> Float -> Float -> a -> b) -> DataSet a -> DataSet b
aggregateMap3 ( key1, predicate1, op1 ) ( key2, predicate2, op2 ) ( key3, predicate3, op3 ) f (DataSet list) =
    let
        aggregated1 : Dict key1 Float
        aggregated1 =
            list
                |> List.filter predicate1
                |> aggregateHelp key1 op1

        aggregated2 : Dict key2 Float
        aggregated2 =
            list
                |> List.filter predicate2
                |> aggregateHelp key2 op2

        aggregated3 : Dict key3 Float
        aggregated3 =
            list
                |> List.filter predicate3
                |> aggregateHelp key3 op3
    in
    list
        |> List.map
            (\a ->
                a
                    |> f
                        (aggregated1 |> Dict.get (key1 a) |> Maybe.withDefault 0)
                        (aggregated2 |> Dict.get (key2 a) |> Maybe.withDefault 0)
                        (aggregated3 |> Dict.get (key3 a) |> Maybe.withDefault 0)
            )
        |> DataSet


aggregateHelp : (a -> key) -> AggregateOp a -> List a -> Dict key Float
aggregateHelp getKey aggregateOp list =
    let
        aggregate : (a -> Float) -> (Float -> Float -> Float) -> Dict key Float
        aggregate field op =
            list
                |> List.foldl
                    (\a dict ->
                        dict
                            |> Dict.update (getKey a)
                                (\currentValue ->
                                    case currentValue of
                                        Nothing ->
                                            Just (field a)

                                        Just value ->
                                            Just (op value (field a))
                                )
                    )
                    Dict.empty

        combine : (Float -> Float -> Float) -> Dict key Float -> Dict key Float -> Dict key Float
        combine f dictA dictB =
            dictA
                |> Dict.map
                    (\key a ->
                        dictB
                            |> Dict.get key
                            |> Maybe.withDefault 0
                            |> f a
                    )

        sum : (a -> Float) -> Dict key Float
        sum field =
            aggregate field (+)
    in
    case aggregateOp of
        Count ->
            sum (always 1)

        Sum field ->
            sum field

        Avg field ->
            combine (/)
                (sum field)
                (sum (always 1))

        Min field ->
            aggregate field min

        Max field ->
            aggregate field max

        WAvg weight value ->
            combine (/)
                (sum (\a -> weight a * value a))
                (sum weight)
