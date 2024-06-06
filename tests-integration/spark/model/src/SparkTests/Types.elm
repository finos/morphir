module SparkTests.Types exposing (AntiqueSubset)

import SparkTests.DataDefinition.Persistence.Income.AntiqueShop exposing (Product)


{-| This is a subset of the fields and types of the record from the Antiques example.
-}
type alias AntiqueSubset =
    { name : String
    , ageOfItem : Float
    , product : Product
    , report : Maybe String
    }
