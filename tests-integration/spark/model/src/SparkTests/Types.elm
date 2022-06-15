module SparkTests.Types exposing (..)

type Title
    = Associate
    | VP
    | ED
    | MD


type alias Record1 =
    { firstName : String
    , lastName : String
    , age : Int
    , title : Title
    }


