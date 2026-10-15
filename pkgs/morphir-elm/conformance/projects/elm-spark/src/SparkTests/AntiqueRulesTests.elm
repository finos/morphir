module SparkTests.AntiqueRulesTests exposing (..)

import SparkTests.DataDefinition.Persistence.Income.AntiqueShop exposing (Antique)
import SparkTests.Rules.Income.Antique exposing (..)

antique_items : List Antique -> List Antique
antique_items antiques =
    List.filter is_item_antique antiques


vintage_items : List Antique -> List Antique
vintage_items antiques =
    List.filter is_item_vintage antiques


worth_thousands_items : List Antique -> List Antique
worth_thousands_items antiques =
    List.filter is_item_worth_thousands antiques


worth_millions_items : List Antique -> List Antique
worth_millions_items antiques =
    List.filter is_item_worth_millions antiques


seized_items : List Antique -> List Antique
seized_items antiques =
    List.filter seize_item antiques
