module SparkTests.FunctionTests exposing (..)

import SparkTests.Types exposing (..)


testCaseBool : List { foo : Bool } -> List { foo : Bool }
testCaseBool source =
    source
        |> List.filter
            (\a ->
                case a.foo of
                    False ->
                        True

                    _ ->
                        False
            )


testCaseFloat : List { foo : Float } -> List { foo : Float }
testCaseFloat source =
    source
        |> List.filter
            (\a ->
                case a.foo of
                    9.99 ->
                        True

                    _ ->
                        False
            )


testCaseInt : List Antique -> List Antique
testCaseInt source =
    source
        |> List.filter
            (\a ->
                case a.ageOfItem of
                    20 ->
                        True

                    5 ->
                        False

                    _ ->
                        False
            )


testCaseString : List Antique -> List Antique
testCaseString source =
    source
        |> List.filter
            (\a ->
                case a.name of
                    "Wooden Chair" ->
                        False

                    _ ->
                        True
            )


testCaseEnum : List Antique -> List Antique
testCaseEnum source =
    source
        |> List.filter
            (\a ->
                case a.product of
                    Paintings ->
                        True

                    Furniture ->
                        True

                    _ ->
                        False
            )


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


testListMinimum : List Antique -> List { min : Maybe Int }
testListMinimum source =
    source
        |> List.map .ageOfItem
        |> (\ages ->
                [ { min =
                        List.minimum ages
                  }
                ]
           )


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
