module SparkTests.DataDefinition.Action exposing (..)

import SparkTests.DataDefinition.Persistence.Expenditure.Bills exposing (Bills)
import SparkTests.DataDefinition.Persistence.Expenditure.Loans exposing (Loans)
import SparkTests.DataDefinition.Persistence.Income.AntiqueShop exposing (Antique)
import SparkTests.DataDefinition.Persistence.Income.ElectronicShop exposing (Electronic)
import SparkTests.DataDefinition.Persistence.Income.GroceryShop exposing (Grocery)


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
