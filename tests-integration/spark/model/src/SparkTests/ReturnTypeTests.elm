module SparkTests.ReturnTypeTests exposing (..)


testReturnListRecords : List { foo : Float } -> List { foo : Float }
testReturnListRecords antiques =
    antiques


testReturnValue1 : List { foo : Float } -> Float
testReturnValue1 antiques =
    antiques
        |> List.map .foo
        |> List.sum


testReturnValue2 : List { foo : Float } -> Int
testReturnValue2 antiques =
    antiques
        |> List.map .foo
        |> List.length


testReturnMaybe : List { foo : Float } -> Maybe Float
testReturnMaybe antiques =
    antiques
        |> List.map .foo
        |> List.minimum
