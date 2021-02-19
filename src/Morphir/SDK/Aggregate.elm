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


module Morphir.SDK.Aggregate exposing
    ( aggregateMap, aggregateMap2, aggregateMap3
    , count, sumOf, minimumOf, maximumOf, averageOf, weightedAverageOf
    , byKey, withFilter
    )

{-| This module contains functions specifically designed to work with large data sets.


# Aggregations

@docs aggregateMap, aggregateMap2, aggregateMap3


## Operators

@docs count, sumOf, minimumOf, maximumOf, averageOf, weightedAverageOf

-}

import AssocList as Dict exposing (Dict)
import Morphir.SDK.Key exposing (Key0, key0)


type Operator a
    = Count
    | Sum (a -> Float)
    | Avg (a -> Float)
    | Min (a -> Float)
    | Max (a -> Float)
    | WAvg (a -> Float) (a -> Float)


{-| Count the number of rows in a group.
-}
count : Aggregation a Key0
count =
    operatorToAggregation Count


{-| Apply a function to each row that returns a numeric value and return the sum of the values.
-}
sumOf : (a -> Float) -> Aggregation a Key0
sumOf =
    Sum >> operatorToAggregation


{-| Apply a function to each row that returns a numeric value and return the average of the values.
-}
averageOf : (a -> Float) -> Aggregation a Key0
averageOf =
    Avg >> operatorToAggregation


{-| Apply a function to each row that returns a numeric value and return the minimum of the values.
-}
minimumOf : (a -> Float) -> Aggregation a Key0
minimumOf =
    Min >> operatorToAggregation


{-| Apply a function to each row that returns a numeric value and return the maximum of the values.
-}
maximumOf : (a -> Float) -> Aggregation a Key0
maximumOf =
    Max >> operatorToAggregation


{-| Apply two functions to each row that returns a numeric value and return the weighted of the values using the first
function to get the weights.
-}
weightedAverageOf : (a -> Float) -> (a -> Float) -> Aggregation a Key0
weightedAverageOf getWeight getValue =
    operatorToAggregation (WAvg getWeight getValue)


type alias Aggregation a key =
    { key : a -> key
    , filter : a -> Bool
    , operator : Operator a
    }


operatorToAggregation : Operator a -> Aggregation a Key0
operatorToAggregation op =
    { key = key0
    , filter = always True
    , operator = op
    }


byKey : (a -> key) -> Aggregation a oldKey -> Aggregation a key
byKey key agg =
    { key = key
    , filter = agg.filter
    , operator = agg.operator
    }


withFilter : (a -> Bool) -> Aggregation a key -> Aggregation a key
withFilter filter agg =
    { agg
        | filter = filter
    }


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
aggregateMap : Aggregation a key1 -> (Float -> a -> b) -> List a -> List b
aggregateMap agg1 f list =
    let
        aggregated1 : Dict key1 Float
        aggregated1 =
            list
                |> List.filter agg1.filter
                |> aggregateHelp agg1.key agg1.operator
    in
    list
        |> List.map
            (\a ->
                f (aggregated1 |> Dict.get (agg1.key a) |> Maybe.withDefault 0) a
            )


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
aggregateMap2 : Aggregation a key1 -> Aggregation a key2 -> (Float -> Float -> a -> b) -> List a -> List b
aggregateMap2 agg1 agg2 f list =
    let
        aggregated1 : Dict key1 Float
        aggregated1 =
            list
                |> List.filter agg1.filter
                |> aggregateHelp agg1.key agg1.operator

        aggregated2 : Dict key2 Float
        aggregated2 =
            list
                |> List.filter agg2.filter
                |> aggregateHelp agg2.key agg2.operator
    in
    list
        |> List.map
            (\a ->
                a
                    |> f
                        (aggregated1 |> Dict.get (agg1.key a) |> Maybe.withDefault 0)
                        (aggregated2 |> Dict.get (agg2.key a) |> Maybe.withDefault 0)
            )


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
aggregateMap3 : Aggregation a key1 -> Aggregation a key2 -> Aggregation a key3 -> (Float -> Float -> Float -> a -> b) -> List a -> List b
aggregateMap3 agg1 agg2 agg3 f list =
    let
        aggregated1 : Dict key1 Float
        aggregated1 =
            list
                |> List.filter agg1.filter
                |> aggregateHelp agg1.key agg1.operator

        aggregated2 : Dict key2 Float
        aggregated2 =
            list
                |> List.filter agg2.filter
                |> aggregateHelp agg2.key agg2.operator

        aggregated3 : Dict key3 Float
        aggregated3 =
            list
                |> List.filter agg3.filter
                |> aggregateHelp agg3.key agg3.operator
    in
    list
        |> List.map
            (\a ->
                a
                    |> f
                        (aggregated1 |> Dict.get (agg1.key a) |> Maybe.withDefault 0)
                        (aggregated2 |> Dict.get (agg2.key a) |> Maybe.withDefault 0)
                        (aggregated3 |> Dict.get (agg3.key a) |> Maybe.withDefault 0)
            )


aggregateHelp : (a -> key) -> Operator a -> List a -> Dict key Float
aggregateHelp getKey op list =
    let
        aggregate : (a -> Float) -> (Float -> Float -> Float) -> List a -> Dict key Float
        aggregate getValue o sourceList =
            sourceList
                |> List.foldl
                    (\a dict ->
                        dict
                            |> Dict.update (getKey a)
                                (\currentValue ->
                                    case currentValue of
                                        Nothing ->
                                            Just (getValue a)

                                        Just value ->
                                            Just (o value (getValue a))
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

        sum : (a -> Float) -> List a -> Dict key Float
        sum getValue sourceList =
            aggregate getValue (+) sourceList
    in
    case op of
        Count ->
            sum (always 1) list

        Sum getValue ->
            sum getValue list

        Avg getValue ->
            combine (/)
                (sum getValue list)
                (sum (always 1) list)

        Min getValue ->
            aggregate getValue min list

        Max getValue ->
            aggregate getValue max list

        WAvg getWeight getValue ->
            combine (/)
                (sum (\a -> getWeight a * getValue a) list)
                (sum getWeight list)
