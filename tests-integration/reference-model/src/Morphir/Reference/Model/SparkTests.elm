module Morphir.Reference.Model.SparkTests exposing (..)


type Title
    = Associate
    | VP
    | ED
    | MD


type alias Record1 =
    { firstName : String
    , lastName : String
    , age : Int
    , title : Title
    }


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
                { firstName = String.join " " [ a.firstName, "hello" ]
                , lastName = String.toUpper a.lastName
                , age = a.age
                , title = a.title
                }
            )
        |> List.filter filterFn


foo : List Record1 -> List Record1
foo record1s =
    record1s


testBadAnnotation : List Record1 -> List Title
testBadAnnotation source =
    source
        |> List.map
            (\_ ->
                Associate
            )


filterFn : Record1 -> Bool
filterFn record1 =
    modBy record1.age 2 <= 3
