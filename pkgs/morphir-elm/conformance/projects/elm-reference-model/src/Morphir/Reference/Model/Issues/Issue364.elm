module Morphir.Reference.Model.Issues.Issue364 exposing (..)

import Morphir.SDK.Aggregate exposing (Aggregation, aggregateMap, aggregateMap2, byKey, maximumOf, minimumOf, sumOf)


type alias Input =
    { key1 : String
    , key2 : String
    , value : Float
    }


calculate1 : List Input -> List ( Input, Float )
calculate1 dataSet =
    dataSet
        |> aggregateMap
            (sumOf .value |> byKey .key1)
            (\totalValue input ->
                ( input, totalValue * input.value )
            )


calculate2 : List Input -> List ( Input, Float )
calculate2 dataSet =
    dataSet
        |> aggregateMap2
            (sumOf .value |> byKey .key1)
            (minimumOf .value |> byKey .key1)
            (\totalValue minValue input ->
                ( input, totalValue / minValue * input.value )
            )
