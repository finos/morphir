module Morphir.Reference.Model.Sample.DataDefinition.Action exposing (..)

import Morphir.Reference.Model.Sample.DataDefinition.Persistence.Expenditure.Bills exposing (Bills)
import Morphir.Reference.Model.Sample.DataDefinition.Persistence.Expenditure.Loans exposing (Loans)
import Morphir.Reference.Model.Sample.DataDefinition.Persistence.Income.AntiqueShop exposing (Antique)
import Morphir.Reference.Model.Sample.DataDefinition.Persistence.Income.ElectronicShop exposing (Electronic)
import Morphir.Reference.Model.Sample.DataDefinition.Persistence.Income.GroceryShop exposing (Grocery)


type alias Action =
    { income : Income
    , expenditure : Expenditure
    }


type alias Income =
    { antique : Antique
    , grocery : Grocery
    , electronic : Electronic
    }


type alias Expenditure =
    { bills : Bills
    , loans : Loans
    }
