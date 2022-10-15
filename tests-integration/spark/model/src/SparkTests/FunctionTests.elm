module SparkTests.FunctionTests exposing (..)

import SparkTests.DataDefinition.Persistence.Income.AntiqueShop exposing (Product(..))
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


testCaseInt : List { foo : Int } -> List { foo : Int }
testCaseInt source =
    source
        |> List.filter
            (\a ->
                case a.foo of
                    20 ->
                        True

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
        |> List.filter (\a -> a.ageOfItem == 20.0)


testWhere2 : List AntiqueSubset -> List AntiqueSubset
testWhere2 source =
    source
        |> List.filter
            (\a ->
                if a.ageOfItem == 20.0 then
                    False

                else
                    True
            )


testWhere3 : List AntiqueSubset -> List AntiqueSubset
testWhere3 source =
    source
        |> List.filter
            (\a ->
                if a.ageOfItem <= 20.0 then
                    False

                else if a.ageOfItem > 20.0 && a.ageOfItem < 23.0 then
                    False

                else
                    True
            )


testSelect1 : List AntiqueSubset -> List { foo : String, newName : String, newReport : Maybe String, product : Product }
testSelect1 source =
    source
        |> List.map
            (\a ->
                { foo =
                    if a.ageOfItem >= 20.0 then
                        "old"

                    else
                        "new"
                , newName = a.name
                , newReport = a.report
                , product = a.product
                }
            )


testSelect3 : List AntiqueSubset -> List { ageOfItem : Float }
testSelect3 source =
    source
        |> List.map (\record -> { ageOfItem = record.ageOfItem })


testSelect4 : List AntiqueSubset -> List Float
testSelect4 source =
    source
        |> List.map .ageOfItem


testFilter : List AntiqueSubset -> List AntiqueSubset
testFilter source =
    source |> List.filter filterFn


testFilter2 : List AntiqueSubset -> List AntiqueSubset
testFilter2 source =
    source |> List.filter (filterFnWithVar 17.0)


testListMinimum : List AntiqueSubset -> List { foo : Maybe Float }
testListMinimum source =
    source
        |> List.map .ageOfItem
        |> (\ages ->
                [ { foo =
                        List.minimum ages
                  }
                ]
           )


testListMaximum : List AntiqueSubset -> List { foo : Maybe Float }
testListMaximum source =
    source
        |> List.map .ageOfItem
        |> (\ages ->
                [ { foo =
                        List.maximum ages
                  }
                ]
           )


testNameMaximum : List AntiqueSubset -> List { foo : Maybe String }
testNameMaximum source =
    source
        |> List.map .name
        |> (\names ->
                [ { foo =
                        List.maximum names
                  }
                ]
           )


testMapAndFilter : List AntiqueSubset -> List AntiqueSubset
testMapAndFilter source =
    source
        |> List.map
            (\a ->
                { name = String.concat [ a.name, " very old" ]
                , report = Maybe.map String.toUpper a.report
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
                , report = Maybe.map String.toUpper a.report
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
                , report = Maybe.map String.toUpper a.report
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
            20.0
    in
    record.ageOfItem
        >= qualifiedYearsToBeCalledAntiqueSubset
        && (record.name == "Bowie Knife")


testLetBinding : List AntiqueSubset -> List AntiqueSubset
testLetBinding source =
    source
        |> List.filter item_filter


testLetDef : List AntiqueSubset -> List AntiqueSubset
testLetDef source =
    let
        exact1 = 5.0
        exact2 = 7.0
        max = 20.0
        min = 10.0
        not = 15.0
    in
    source
        |> List.filter
            (\antique ->
                (antique.ageOfItem <= max) && (antique.ageOfItem >= min) && (antique.ageOfItem /= not) || (antique.ageOfItem == exact1) || (antique.ageOfItem == exact2)
            )


filterFn : AntiqueSubset -> Bool
filterFn record1 =
    modBy (floor record1.ageOfItem) 2 <= 3


filterFnWithVar : Float -> AntiqueSubset -> Bool
filterFnWithVar max record =
    max
        |> (\ageOfItem maximumAllowedAge ->
                ageOfItem <= (maximumAllowedAge + max)
           )
            record.ageOfItem


testListSum : List AntiqueSubset -> List { foo : Float }
testListSum source =
    source
        |> List.map .ageOfItem
        |> (\ages ->
                [ { foo =
                        List.sum ages
                  }
                ]
           )


testListLength : List AntiqueSubset -> List { foo : Int }
testListLength source =
    source
        |> List.map .name
        |> (\names ->
                [ { foo =
                        List.length names
                  }
                ]
           )
