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


testReturnRecord : List { ageOfItem : Float } -> { sum : Float, min : Maybe Float }
testReturnRecord antiques =
    { min = antiques |> List.map .ageOfItem |> List.minimum
    , sum = antiques |> List.map .ageOfItem |> List.sum
    }

testReturnApplyRecord : List { ageOfItem : Float } -> { sum : Float, min : Maybe Float }
testReturnApplyRecord antiques =
    antiques
        |> List.map .ageOfItem
        |> (\ages ->
                { min = List.minimum ages
                , sum = List.sum ages
                }
           )

testReturnInlineApplyRecord : List { ageOfItem : Float } -> { sum : Float, min : Maybe Float }
testReturnInlineApplyRecord antiques =
    let
        getAll : List Float -> Float
        getAll values =
            List.sum values

        getLeast : List Float -> Maybe Float
        getLeast values =
            values
                |> List.minimum
    in
    antiques
        |> List.map .ageOfItem
        |> (\ages ->
                { min = getLeast ages
                , sum = getAll ages
                }
            )
