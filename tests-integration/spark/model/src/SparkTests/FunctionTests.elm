module SparkTests.FunctionTests exposing (..)

import SparkTests.Types exposing (..)

testFrom : List Antique -> List Antique
testFrom source =
    source


testWhere1 : List Antique -> List Antique
testWhere1 source =
    source
        |> List.filter (\a -> a.ageOfItem == 20)


testWhere2 : List Antique -> List Antique
testWhere2 source =
    source
        |> List.filter
            (\a ->
                if a.ageOfItem == 20 then
                    False

                else
                    True
            )


testWhere3 : List Antique -> List Antique
testWhere3 source =
    source
        |> List.filter
            (\a ->
                if a.ageOfItem <= 20 then
                    False

                else if a.ageOfItem > 20 && a.ageOfItem < 23 then
                    False

                else
                    True
            )


testSelect1 : List Antique -> List { newName : String, newReport : String, foo : String, product : Product }
testSelect1 source =
    source
        |> List.map
            (\a ->
                { newName = a.name
                , newReport = a.report
                , foo =
                    if a.ageOfItem >= 20 then
                        "old"

                    else
                        "new"
                , product = a.product
                }
            )


testSelect3 : List Antique -> List { ageOfItem : Int }
testSelect3 source =
    source
        |> List.map (\record -> { ageOfItem = record.ageOfItem })


testSelect4 : List Antique -> List Int
testSelect4 source =
    source
        |> List.map .ageOfItem


testFilter : List Antique -> List Antique
testFilter source =
    source |> List.filter filterFn


testFilter2 : List Antique -> List Antique
testFilter2 source =
    source |> List.filter (filterFnWithVar 17)


testMapAndFilter : List Antique -> List Antique
testMapAndFilter source =
    source
        |> List.map
            (\a ->
                { name = String.concat [ a.name, " very old" ]
                , report = String.toUpper a.report
                , ageOfItem = a.ageOfItem
                , product = a.product
                }
            )
        |> List.filter filterFn


testMapAndFilter2 : List Antique -> List Antique
testMapAndFilter2 source =
    source
        |> List.map
            (\a ->
                { name = String.reverse a.name
                , report = String.toUpper a.report
                , ageOfItem = a.ageOfItem
                , product = a.product
                }
            )
        |> List.filter filterFn


testMapAndFilter3 : List Antique -> List Antique
testMapAndFilter3 source =
    source
        |> List.map
            (\a ->
                { name = String.replace "." " " a.name
                , report = String.toUpper a.report
                , ageOfItem = a.ageOfItem
                , product = a.product
                }
            )
        |> List.filter filterFn


testBadAnnotation : List Antique -> List Product
testBadAnnotation source =
    source
        |> List.map
            (\_ ->
                Knife
            )


item_filter : Antique -> Bool
item_filter record =
    let
        qualifiedYearsToBeCalledAntique =
            20
    in
    record.ageOfItem
        >= qualifiedYearsToBeCalledAntique
        && (record.name == "Bowie Knife")


testLetBinding : List Antique -> List Antique
testLetBinding source =
    source
        |> List.filter item_filter


filterFn : Antique -> Bool
filterFn record1 =
    modBy record1.ageOfItem 2 <= 3


filterFnWithVar : Int -> Antique -> Bool
filterFnWithVar max record =
    max
        |> (\ageOfItem maximumAllowedAge ->
                ageOfItem <= (maximumAllowedAge + max)
           )
            record.ageOfItem
