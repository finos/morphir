module Morphir.Reference.Model.Issues.Issue364 exposing (..)

import Morphir.SDK.Aggregate exposing (Aggregation, aggregateMap, aggregateMap2, byKey, maximumOf, sumOf)


type alias Input =
    { key1 : String
    , key2 : String
    , value : Float
    }


calculate : List Input -> List ( Input, Float )
calculate dataSet =
    dataSet
        |> aggregateMap
            (sumOf .value |> byKey .key1)
            (\totalValue input ->
                ( input, totalValue * input.value )
            )
