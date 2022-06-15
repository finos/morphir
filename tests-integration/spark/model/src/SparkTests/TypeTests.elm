module SparkTests.TypeTests exposing (..)

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

testString : List { foo : String } -> List { foo : String }
testString source =
    source
        |> List.filter
            (\a ->
                a.foo == "bar"
            )

