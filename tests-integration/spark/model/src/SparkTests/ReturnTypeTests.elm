module SparkTests.ReturnTypeTests exposing (..)

testReturnListRecords : List { ageOfItem : Float } -> List { ageOfItem : Float }
testReturnListRecords antiques =
    antiques

testReturnValue1 : List { ageOfItem : Float } -> Float
testReturnValue1 antiques =
    antiques
        |> List.map .ageOfItem
        |> List.sum

testReturnValue2 : List { ageOfItem : Float } -> Int
testReturnValue2 antiques =
    antiques
        |> List.map .ageOfItem
        |> List.length

testReturnMaybe : List { ageOfItem : Float } -> Maybe Float
testReturnMaybe antiques =
    antiques
        |> List.map .ageOfItem
        |> List.minimum

--testReturnRecord1 : List { ageOfItem : Float } -> { value : Float }
--testReturnRecord1 antiques =
--    { value = antiques |> List.map .ageOfItem |> List.sum
--    }
--
--testReturnRecord2 : List { ageOfItem : Float } -> { value1 : Float, value2 : float }
--testReturnRecord2 antiques =
--    { value1 = antiques |> List.map .ageOfItem |> List.sum
--    , value2 = antiques |> List.map .ageOfItem |> List.product
--    }
--
--testTuple : List { ageOfItem : Float } -> (Float, Maybe Float)
--testTuple antiques =
--    ( antiques |> List.map .ageOfItem |> List.sum
--    , antiques |> List.map .ageOfItem |> List.minimum
--    )

