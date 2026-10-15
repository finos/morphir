module SparkTests.Rules.Income.Antique exposing (..)

import SparkTests.DataDefinition.Field.Category exposing (Category(..))
import SparkTests.DataDefinition.Field.Price exposing (Price)
import SparkTests.DataDefinition.Field.Report exposing (FeedBack(..))
import SparkTests.DataDefinition.Persistence.Income.AntiqueShop exposing (Antique, Product(..))


type alias PriceRange =
    ( Price, Price )


is_item_antique : Antique -> Bool
is_item_antique antique =
    let
        qualifiedYearsToBeCalledAntique =
            100
    in
    antique.ageOfItem
        >= qualifiedYearsToBeCalledAntique
        && List.member antique.product [ Furniture, Paintings ]


is_item_vintage : Antique -> Bool
is_item_vintage antique =
    List.member antique.product [ Furniture, Paintings ]
        && (let
                qualifiedYearsToBeCalledVintage =
                    20
            in
            antique.ageOfItem
                == qualifiedYearsToBeCalledVintage
           )


is_item_worth_thousands : Antique -> Bool
is_item_worth_thousands antique =
    is_item_vintage antique
        || is_item_antique antique
        && List.member antique.product [ Furniture, Paintings ]
        && (antique.category
                |> Maybe.map
                    (\category ->
                        case category of
                            PaintCollections ->
                                True

                            SimpleToolCollection ->
                                True

                            _ ->
                                False
                    )
                |> Maybe.withDefault False
           )


is_item_worth_millions : Antique -> Bool
is_item_worth_millions antique =
    is_item_antique antique
        && List.member antique.product [ Paintings, HistoryWritings, Furniture ]
        && (antique.category
                |> Maybe.map
                    (\category ->
                        case category of
                            Diary ->
                                True

                            PaintCollections ->
                                True

                            HouseHoldCollection ->
                                True

                            _ ->
                                False
                    )
                |> Maybe.withDefault False
           )
        && antique.handMade
        == True
        && antique.requiresExpert
        == True
        && (antique.expertFeedback
                |> Maybe.map
                    (\expertReport ->
                        case expertReport of
                            Genuine ->
                                True

                            _ ->
                                False
                    )
                |> Maybe.withDefault False
           )


seize_item : Antique -> Bool
seize_item antique =
    (is_item_antique antique == False)
        && (is_item_vintage antique == False)
        && antique.requiresExpert
        == True
        || antique.requiresExpert
        == False
        && (antique.expertFeedback == Just Fake)
        && (antique.report == Nothing)


type alias Report =
    { antiqueValue : Float
    , seizedValue : Float
    , vintageValue : Float
    }


report : List Antique -> Report
report antiques =
    { antiqueValue =
        antiques
            |> List.filter is_item_antique
            |> List.map .priceValue
            |> List.sum
    , seizedValue =
        antiques
            |> List.filter seize_item
            |> List.map .priceValue
            |> List.sum
    , vintageValue =
        antiques
            |> List.filter is_item_vintage
            |> List.map .priceValue
            |> List.sum
    }
