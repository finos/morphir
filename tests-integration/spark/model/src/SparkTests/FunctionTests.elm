module SparkTests.FunctionTests exposing (..)

import SparkTests.DataDefinition.Persistence.Income.AntiqueShop exposing (..)
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


testCaseInt : List AntiqueSubset -> List AntiqueSubset
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


testCaseString : List AntiqueSubset -> List AntiqueSubset
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


testCaseEnum : List AntiqueSubset -> List AntiqueSubset
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


testFrom : List AntiqueSubset -> List AntiqueSubset
testFrom source =
    source


testWhere1 : List AntiqueSubset -> List AntiqueSubset
testWhere1 source =
    source
        |> List.filter (\a -> a.ageOfItem == 20)


testWhere2 : List AntiqueSubset -> List AntiqueSubset
testWhere2 source =
    source
        |> List.filter
            (\a ->
                if a.ageOfItem == 20 then
                    False

                else
                    True
            )


testWhere3 : List AntiqueSubset -> List AntiqueSubset
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


testSelect1 : List AntiqueSubset -> List { newName : String, newReport : String, foo : String, product : Product }
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


testSelect3 : List AntiqueSubset -> List { ageOfItem : Int }
testSelect3 source =
    source
        |> List.map (\record -> { ageOfItem = record.ageOfItem })


testSelect4 : List AntiqueSubset -> List Int
testSelect4 source =
    source
        |> List.map .ageOfItem


testFilter : List AntiqueSubset -> List AntiqueSubset
testFilter source =
    source |> List.filter filterFn


testFilter2 : List AntiqueSubset -> List AntiqueSubset
testFilter2 source =
    source |> List.filter (filterFnWithVar 17)


testListMinimum : List AntiqueSubset -> List { min : Maybe Int }
testListMinimum source =
    source
        |> List.map .ageOfItem
        |> (\ages ->
                [ { min =
                        List.minimum ages
                  }
                ]
           )


testListMaximum : List AntiqueSubset -> List { max : Maybe Int }
testListMaximum source =
    source
        |> List.map .ageOfItem
        |> (\ages ->
                [ { max =
                        List.maximum ages
                  }
                ]
           )


testMapAndFilter : List AntiqueSubset -> List AntiqueSubset
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


testMapAndFilter2 : List AntiqueSubset -> List AntiqueSubset
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


testMapAndFilter3 : List AntiqueSubset -> List AntiqueSubset
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


testBadAnnotation : List AntiqueSubset -> List Product
testBadAnnotation source =
    source
        |> List.map
            (\_ ->
                Knife
            )


item_filter : AntiqueSubset -> Bool
item_filter record =
    let
        qualifiedYearsToBeCalledAntiqueSubset =
            20
    in
    record.ageOfItem
        >= qualifiedYearsToBeCalledAntiqueSubset
        && (record.name == "Bowie Knife")


testLetBinding : List AntiqueSubset -> List AntiqueSubset
testLetBinding source =
    source
        |> List.filter item_filter


filterFn : AntiqueSubset -> Bool
filterFn record1 =
    modBy record1.ageOfItem 2 <= 3


filterFnWithVar : Int -> AntiqueSubset -> Bool
filterFnWithVar max record =
    max
        |> (\ageOfItem maximumAllowedAge ->
                ageOfItem <= (maximumAllowedAge + max)
           )
            record.ageOfItem
