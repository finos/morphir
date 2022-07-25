module SparkTests.Types exposing (..)

import SparkTests.DataDefinition.Persistence.Income.AntiqueShop exposing (Product)


{-| This is a subset of the fields and types of the record from the Antiques example.
-}
type alias AntiqueSubset =
    { name : String
    , ageOfItem : Int
    , product : Product
    , report : String
    }
