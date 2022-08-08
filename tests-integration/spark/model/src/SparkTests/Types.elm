module SparkTests.Types exposing (..)

type Product
    = Paintings
    | Knife
    | Plates
    | Furniture
    | HistoryWritings
    


{-| This is a subset of the fields and types of the record from the Antiques example.
-}
type alias AntiqueSubset =
    { name : String
    , ageOfItem : Float
    , product : Product
    , report : String
    }
