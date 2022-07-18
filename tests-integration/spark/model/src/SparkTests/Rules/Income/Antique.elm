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
        || (is_item_vintage antique == False)
        && antique.requiresExpert
        == True
        || antique.requiresExpert
        == False
        && (antique.expertFeedback == Just Fake)
        && (antique.report == Nothing)


christmas_bonanza_15percent_priceRange : List Antique -> PriceRange
christmas_bonanza_15percent_priceRange antiqueList =
    let
        bonanzaDiscount =
            0.15

        getPriceValue : List Float -> String -> Float
        getPriceValue priceValues order =
            if order == "min" then
                case priceValues |> List.minimum of
                    Just va ->
                        va

                    Nothing ->
                        0.0

            else
                case priceValues |> List.maximum of
                    Just va ->
                        va

                    Nothing ->
                        0.0
    in
    antiqueList
        |> List.filter (\item -> is_item_antique item || is_item_vintage item)
        |> List.map (\item -> item.priceValue * bonanzaDiscount)
        |> (\lstOfPriceValues ->
                ( getPriceValue lstOfPriceValues "min"
                , getPriceValue lstOfPriceValues "max"
                )
           )
