module SparkTests.AggregationTests exposing (..)

import Morphir.SDK.Aggregate exposing (aggregate, averageOf, count, groupBy, maximumOf, minimumOf, sumOf, withFilter)
import SparkTests.DataDefinition.Persistence.Income.AntiqueShop exposing (Antique, Product)


testAggregateSum : List Antique -> List { product : Product, sum : Float }
testAggregateSum antiques =
    antiques
        |> groupBy .product
        |> aggregate
            (\key inputs ->
                { product = key
                , sum = inputs (sumOf .ageOfItem)
                }
            )


testAggregateCount : List Antique -> List { product : Product, count : Float }
testAggregateCount antiques =
    antiques
        |> groupBy .product
        |> aggregate
            (\key inputs ->
                { product = key
                , count = inputs count
                }
            )


testAggregateAverage : List Antique -> List { product : Product, average : Float }
testAggregateAverage antiques =
    antiques
        |> groupBy .product
        |> aggregate
            (\key inputs ->
                { product = key
                , average = inputs (averageOf .ageOfItem)
                }
            )


testAggregateMinimum : List Antique -> List { product : Product, minimum : Float }
testAggregateMinimum antiques =
    antiques
        |> groupBy .product
        |> aggregate
            (\key inputs ->
                { product = key
                , minimum = inputs (minimumOf .ageOfItem)
                }
            )


testAggregateMaximum : List Antique -> List { product : Product, maximum : Float }
testAggregateMaximum antiques =
    antiques
        |> groupBy .product
        |> aggregate
            (\key inputs ->
                { product = key
                , maximum = inputs (maximumOf .ageOfItem)
                }
            )


testAggregateFilterAll : List Antique -> List { product : Product, count : Float }
testAggregateFilterAll antiques =
    antiques
        |> List.filter
            (\item ->
                item.ageOfItem >= 20.0
            )
        |> groupBy .product
        |> aggregate
            (\key inputs ->
                { product = key
                , count = inputs count
                }
            )


testAggregateFilterOneCount : List Antique -> List { product : Product, vintage : Float, all : Float }
testAggregateFilterOneCount antiques =
    antiques
        |> groupBy .product
        |> aggregate
            (\key inputs ->
                { product = key
                , all = inputs count
                , vintage = inputs (count |> withFilter (\a -> a.ageOfItem >= 20.0))
                }
            )


testAggregateFilterOneMin : List Antique -> List { product : Product, youngest_qualifying : Float }
testAggregateFilterOneMin antiques =
    antiques
        |> groupBy .product
        |> aggregate
            (\key inputs ->
                { product = key
                , youngest_qualifying = inputs (minimumOf .ageOfItem |> withFilter (\a -> a.ageOfItem >= 20.0))
                }
            )


testAggregateRenameKey : List Antique -> List { itemType : Product, count : Float }
testAggregateRenameKey antiques =
    antiques
        |> groupBy .product
        |> aggregate
            (\key inputs ->
                { itemType = key
                , count = inputs count
                }
            )
