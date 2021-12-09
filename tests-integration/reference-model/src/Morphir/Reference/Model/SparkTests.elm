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


testSelect1 : List Record1 -> List { nickname : String, familyName : String, foo : String }
testSelect1 source =
    source
        |> List.map
            (\a ->
                { nickname = a.firstName
                , familyName = a.lastName
                , foo =
                    if a.age == 13 then
                        "bar"

                    else
                        "baz"
                }
            )
