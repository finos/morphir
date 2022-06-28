module SparkTests.FunctionTests exposing (..)

import SparkTests.Types exposing (..)

testFrom : List Record1 -> List Record1
testFrom source =
    source


testWhere1 : List Record1 -> List Record1
testWhere1 source =
    source
        |> List.filter (\a -> a.age == 13)


testWhere2 : List Record1 -> List Record1
testWhere2 source =
    source
        |> List.filter
            (\a ->
                if a.age == 13 then
                    False

                else
                    True
            )


testWhere3 : List Record1 -> List Record1
testWhere3 source =
    source
        |> List.filter
            (\a ->
                if a.age <= 13 then
                    False

                else if a.age > 13 && a.age < 15 then
                    False

                else
                    True
            )


testSelect1 : List Record1 -> List { nickname : String, familyName : String, foo : String }
testSelect1 source =
    source
        |> List.map
            (\a ->
                { nickname = a.firstName
                , familyName = a.lastName
                , foo =
                    if a.age >= 13 then
                        "bar"

                    else
                        "baz"
                }
            )


testSelect3 : List Record1 -> List { age : Int }
testSelect3 source =
    source
        |> List.map (\record -> { age = record.age })


testSelect4 : List Record1 -> List Int
testSelect4 source =
    source
        |> List.map .age


testFilter : List Record1 -> List Record1
testFilter source =
    source |> List.filter filterFn


testFilter2 : List Record1 -> List Record1
testFilter2 source =
    source |> List.filter (filterFnWithVar 17)


testMapAndFilter : List Record1 -> List Record1
testMapAndFilter source =
    source
        |> List.map
            (\a ->
                { firstName = String.concat [ a.firstName, " hello" ]
                , lastName = String.toUpper a.lastName
                , age = a.age
                , title = a.title
                }
            )
        |> List.filter filterFn


testMapAndFilter2 : List Record1 -> List Record1
testMapAndFilter2 source =
    source
        |> List.map
            (\a ->
                { firstName = String.reverse a.firstName
                , lastName = String.toUpper a.lastName
                , age = a.age
                , title = a.title
                }
            )
        |> List.filter filterFn


testMapAndFilter3 : List Record1 -> List Record1
testMapAndFilter3 source =
    source
        |> List.map
            (\a ->
                { firstName = String.replace "." " " a.firstName
                , lastName = String.toUpper a.lastName
                , age = a.age
                , title = a.title
                }
            )
        |> List.filter filterFn


testBadAnnotation : List Record1 -> List Title
testBadAnnotation source =
    source
        |> List.map
            (\_ ->
                Associate
            )


item_filter : Record1 -> Bool
item_filter record =
    let
        qualifiedYearsToBeCalledAntique =
            100
    in
    record.age
        >= qualifiedYearsToBeCalledAntique
        && (record.firstName == "Micheal")


testLetBinding : List Record1 -> List Record1
testLetBinding source =
    source
        |> List.filter item_filter


filterFn : Record1 -> Bool
filterFn record1 =
    modBy record1.age 2 <= 3


filterFnWithVar : Int -> Record1 -> Bool
filterFnWithVar max record =
    max
        |> (\age maximumAllowedAge ->
                age <= (maximumAllowedAge + max)
           )
            record.age
