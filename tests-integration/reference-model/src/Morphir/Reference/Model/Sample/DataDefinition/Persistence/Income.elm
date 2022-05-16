module Morphir.Reference.Model.Sample.DataDefinition.Persistence.Income exposing (..)

import Morphir.Reference.Model.Sample.DataDefinition.Persistence.Income.AntiqueShop exposing (Antique)
import Morphir.Reference.Model.Sample.DataDefinition.Persistence.Income.ElectronicShop exposing (Electronic)
import Morphir.Reference.Model.Sample.DataDefinition.Persistence.Income.GroceryShop exposing (Grocery)


type Income
    = AntiqueShop Antique
    | ElectronicShop Electronic
    | GroceryShop Grocery
