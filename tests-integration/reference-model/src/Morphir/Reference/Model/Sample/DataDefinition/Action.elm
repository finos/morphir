module Morphir.Reference.Model.Sample.DataTables.Action exposing (..)

import Morphir.Reference.Model.Sample.DataDefinition.Field.ElectronicShop exposing (Electronic)
import Morphir.Reference.Model.Sample.DataDefinition.Persistence.Demand.Bills exposing (Bills)
import Morphir.Reference.Model.Sample.DataDefinition.Persistence.Demand.Loans exposing (Loans)
import Morphir.Reference.Model.Sample.DataDefinition.Persistence.Supply.AntiqueShop exposing (Antique)
import Morphir.Reference.Model.Sample.DataDefinition.Persistence.Supply.GroceryShop exposing (Grocery)


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
