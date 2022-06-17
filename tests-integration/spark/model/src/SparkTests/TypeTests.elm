module SparkTests.TypeTests exposing (..)

import SparkTests.Types exposing (..)

testBool : List { foo : Bool } -> List { foo : Bool }
testBool source =
    source
        |> List.filter
            (\a ->
                a.foo == False
            )

testFloat : List { foo : Float } -> List { foo : Float }
testFloat source =
    source
        |> List.filter
            (\a ->
                a.foo == 9.99
            )

testInt : List { foo : Int } -> List { foo : Int }
testInt source =
    source
        |> List.filter
            (\a ->
                a.foo == 13
            )

testMaybeBoolConditionalNull : List { foo : Maybe Bool } -> List { foo : Maybe Bool }
testMaybeBoolConditionalNull source =
    source
        |> List.filter
            (\a ->
                a.foo == Nothing
            )

testMaybeBoolConditionalNotNull : List { foo : Maybe Bool } -> List { foo : Maybe Bool }
testMaybeBoolConditionalNotNull source =
    source
        |> List.filter
            (\a ->
                a.foo /= Nothing
            )

testString : List { foo : String } -> List { foo : String }
testString source =
    source
        |> List.filter
            (\a ->
                a.foo == "bar"
            )

testEnum : List { title : Title } -> List { title : Title }
testEnum source =
    source
        |> List.filter
            (\a ->
                a.title == ED
            )

