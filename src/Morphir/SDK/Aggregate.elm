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
    ( Aggregation
    , groupBy, aggregate
    , aggregateMap, aggregateMap2, aggregateMap3
    , count, sumOf, minimumOf, maximumOf, averageOf, weightedAverageOf
    , byKey, withFilter
    )

{-| This module contains functions specifically designed to work with large data sets.


# Aggregations

@docs Aggregation
@docs groupBy, aggregate
@docs aggregateMap, aggregateMap2, aggregateMap3


## Operators

@docs count, sumOf, minimumOf, maximumOf, averageOf, weightedAverageOf
@docs byKey, withFilter

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


{-| Type that represents an aggregation on a type `a` with a key of `key`. It encapsulates the following information:

  - `key` is a function that gets the key of each `a`
  - `filter` is a function used for filtering items out before the aggregation. This can be set to `always True` to not do any filtering.
  - `operator` is the aggregation operation to apply (count, sum, average, ...)

-}
type alias Aggregation a key =
    { key : a -> key
    , filter : a -> Bool
    , operator : Operator a
    }


type alias Aggregator a key =
    Aggregation a key -> Float


operatorToAggregation : Operator a -> Aggregation a Key0
operatorToAggregation op =
    { key = key0
    , filter = always True
    , operator = op
    }


{-| Changes the key of an aggregation. Usage:

    count
        |> byKey .key1
        == { key = .key1
           , filter = always True
           , operator = Count
           }

-}
byKey : (a -> key) -> Aggregation a Key0 -> Aggregation a key
byKey key agg =
    { key = key
    , filter = agg.filter
    , operator = agg.operator
    }


{-| Adds a filter to an aggregation. Usage:

    count
        |> withFilter (\a -> a.value < 0)
        == { key = key0
           , filter = \a -> a.value < 0
           , operator = Count
           }

-}
withFilter : (a -> Bool) -> Aggregation a key -> Aggregation a key
withFilter filter agg =
    { agg
        | filter = filter
    }


{-| Map function that provides an aggregated value to the mapping function. The first argument is a tuple where the
first element is a function that defines the aggregation key, the second element is predicate that allows you to filter
out certain rows from the aggregation and the third argument is the aggregation operation to apply. Usage:

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

        testDataSet
            |> aggregateMap
                (sumOf .value |> byKey .key1)
                    (\\totalValue input ->
                        ( input, totalValue / input.value )
                    )
            {- ==
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
                (sumOf .value |> byKey .key1)
                (maximumOf .value |> byKey .key2)
                (\totalValue maxValue input ->
                    ( input, totalValue * maxValue / input.value )
                )
            {- ==
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
                (sumOf .value |> byKey .key1)
                (maximumOf .value |> byKey .key2)
                (minimumOf .value |> byKey (key2 .key1 .key2))
                (\totalValue maxValue minValue input ->
                    ( input, totalValue * maxValue / input.value + minValue )
                )
            {- ==
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
        agg : (a -> Float) -> (Float -> Float -> Float) -> List a -> Dict key Float
        agg getValue o sourceList =
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
            agg getValue (+) sourceList
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
            agg getValue min list

        Max getValue ->
            agg getValue max list

        WAvg getWeight getValue ->
            combine (/)
                (sum (\a -> getWeight a * getValue a) list)
                (sum getWeight list)


{-| Group a list of items into a dictionary. Grouping is done using a function that returns a key for each item.
The resulting dictionary will use those keys as the key of each entry in the dictionary and values will be lists of
items for each key.

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

    testDataSet
        |> groupBy .key1
            {- == Dict.fromList
                        [ ( "k1_1"
                          , [ TestInput1 "k1_1" "k2_1" 1
                            , TestInput1 "k1_1" "k2_1" 2
                            , TestInput1 "k1_1" "k2_2" 3
                            , TestInput1 "k1_1" "k2_2" 4
                            ]
                        , ( "k1_2",
                          , [ TestInput1 "k1_2" "k2_1" 5
                            , TestInput1 "k1_2" "k2_1" 6
                            , TestInput1 "k1_2" "k2_2" 7
                            , TestInput1 "k1_2" "k2_2" 8
                            ]
                        ]
            -}

-}
groupBy : (a -> key) -> List a -> Dict key (List a)
groupBy getKey list =
    list
        |> List.foldl
            (\a dictSoFar ->
                dictSoFar
                    |> Dict.update (getKey a)
                        (\maybeListOfValues ->
                            case maybeListOfValues of
                                Just listOfValues ->
                                    Just (a :: listOfValues)

                                Nothing ->
                                    Just [ a ]
                        )
            )
            Dict.empty


{-| Aggregates a dictionary that contains lists of items as values into a list that contains exactly one item per key.
The first argument is a function that takes a key and an aggregator and it should return a single item in the resulting
list. The aggregator is a function that takes one of the aggregation functions in this module (`count`, `sumOf`,
`minimumOf`, ...) and returns the aggregated value for the list of values in the input dictionary.

    grouped =
        Dict.fromList
            [ ( "k1_1"
              , [ TestInput1 "k1_1" "k2_1" 1
                , TestInput1 "k1_1" "k2_1" 2
                , TestInput1 "k1_1" "k2_2" 3
                , TestInput1 "k1_1" "k2_2" 4
                ]
            , ( "k1_2",
              , [ TestInput1 "k1_2" "k2_1" 5
                , TestInput1 "k1_2" "k2_1" 6
                , TestInput1 "k1_2" "k2_2" 7
                , TestInput1 "k1_2" "k2_2" 8
                ]
            ]

    grouped
        |> aggregate
            (\key inputs ->
                { key = key
                , count = inputs (count |> withFilter (\a -> a.value < 7))
                , sum = inputs (sumOf .value)
                , max = inputs (maximumOf .value)
                , min = inputs (minimumOf .value)
                }
            )
            {- ==
                [ { key = "k1_1", count = 4, sum = 10, max = 4, min = 1 }
                , { key = "k1_2", count = 2, sum = 26, max = 8, min = 5 }
                ]
            -}

This function is designed to be used in combination with `groupBy`.

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

        testDataSet
            |> groupBy .key1
            |> aggregate
                (\key inputs ->
                    { key = key
                    , count = inputs (count |> withFilter (\a -> a.value < 7))
                    , sum = inputs (sumOf .value)
                    , max = inputs (maximumOf .value)
                    , min = inputs (minimumOf .value)
                    }
                )
                { ==
                    [ { key = "k1_1", count = 4, sum = 10, max = 4, min = 1 }
                    , { key = "k1_2", count = 2, sum = 26, max = 8, min = 5 }
                    ]
                }

-}
aggregate : (key -> Aggregator a Key0 -> b) -> Dict key (List a) -> List b
aggregate f dict =
    dict
        |> Dict.toList
        |> List.map
            (\( key, items ) ->
                f key
                    (\agg ->
                        items
                            |> List.filter agg.filter
                            |> aggregateHelp agg.key agg.operator
                            |> Dict.get (key0 ())
                            |> Maybe.withDefault 0
                    )
            )
