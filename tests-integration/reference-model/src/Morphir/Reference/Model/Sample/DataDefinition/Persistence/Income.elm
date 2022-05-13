module Morphir.Reference.Model.Sample.DataDefinition.Persistence.Income exposing (..)

import Morphir.Reference.Model.Sample.DataDefinition.Field.ElectronicShop exposing (Electronic)
import Morphir.Reference.Model.Sample.DataDefinition.Persistence.Supply.AntiqueShop exposing (Antique)
import Morphir.Reference.Model.Sample.DataDefinition.Persistence.Supply.GroceryShop exposing (Grocery)


type Income
    = AntiqueShop Antique
    | ElectronicShop Electronic
    | GroceryShop Grocery
