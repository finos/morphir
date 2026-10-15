module SparkTests.TypeTests exposing (..)

import SparkTests.DataDefinition.Persistence.Income.AntiqueShop exposing (..)


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


testMaybeBoolConditional : List { foo : Maybe Bool } -> List { foo : Maybe Bool }
testMaybeBoolConditional source =
    source
        |> List.filter
            (\a ->
                a.foo == Just True
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


testMaybeFloat : List { foo : Maybe Float } -> List { foo : Maybe Float }
testMaybeFloat source =
    source
        |> List.filter
            (\a ->
                if a.foo == Just 9.99 then
                    True

                else if a.foo /= Nothing then
                    True

                else
                    False
            )


testMaybeInt : List { foo : Maybe Int } -> List { foo : Maybe Int }
testMaybeInt source =
    source
        |> List.filter
            (\a ->
                if a.foo == Just 13 then
                    True

                else if a.foo /= Nothing then
                    True

                else
                    False
            )


testMaybeMapDefault : List { foo : Maybe Bool } -> List { foo : Maybe Bool }
testMaybeMapDefault source =
    source
        |> List.filter
            (\item ->
                item.foo
                    |> Maybe.map
                        (\a ->
                            if a == False then
                                True

                            else
                                False
                        )
                    |> Maybe.withDefault False
            )


testMaybeString : List { foo : Maybe String } -> List { foo : Maybe String }
testMaybeString source =
    source
        |> List.filter
            (\a ->
                if a.foo == Just "bar" then
                    True

                else if a.foo /= Nothing then
                    True

                else
                    False
            )


testString : List { foo : String } -> List { foo : String }
testString source =
    source
        |> List.filter
            (\a ->
                a.foo == "bar"
            )


testEnum : List { product : Product } -> List { product : Product }
testEnum source =
    source
        |> List.filter
            (\a ->
                a.product == Plates
            )
