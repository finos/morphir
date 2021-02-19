module Morphir.Reference.Model.Issues.Issue364 exposing (..)

import Morphir.SDK.Aggregate exposing (Aggregation, aggregateMap2, byKey, maximumOf, sumOf)


type alias Input =
    { key1 : String
    , key2 : String
    , value : Float
    }


calculate : List Input -> List ( Input, Float )
calculate dataSet =
    let
        agg2 : Aggregation Input String
        agg2 =
            maximumOf .value |> byKey .key2

        agg1 : Aggregation Input String
        agg1 =
            sumOf .value |> byKey .key1
    in
    dataSet
        |> aggregateMap2
            agg1
            agg2
            (\totalValue maxValue input ->
                ( input, totalValue * maxValue / input.value )
            )


calculate2 : List Input -> List ( Input, Float )
calculate2 dataSet =
    dataSet
        |> aggregateMap2
            (sumOf .value |> byKey .key1)
            (maximumOf .value |> byKey .key2)
            (\totalValue maxValue input ->
                ( input, totalValue * maxValue / input.value )
            )
