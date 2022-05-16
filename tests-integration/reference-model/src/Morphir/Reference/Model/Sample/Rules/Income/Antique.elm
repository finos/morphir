module Morphir.Reference.Model.Sample.Rules.Income.Antique exposing (..)

import Morphir.Reference.Model.Sample.DataDefinition.Field.Category exposing (Category(..))
import Morphir.Reference.Model.Sample.DataDefinition.Field.Report exposing (FeedBack(..))
import Morphir.Reference.Model.Sample.DataDefinition.Persistence.Income exposing (Income)
import Morphir.Reference.Model.Sample.DataDefinition.Persistence.Income.AntiqueShop exposing (Antique, Product(..))


applyRules : Income -> List ( String, Float )
applyRules shopItems =
    List.concat
        []


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
