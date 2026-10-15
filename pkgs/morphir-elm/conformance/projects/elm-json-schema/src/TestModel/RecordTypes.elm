module TestModel.RecordTypes exposing (..)
import TestModel.BasicTypes exposing (..)


type alias Resource =
    { resourceName : String
    , address : Address
    }


type alias Address =
    { protocol : Maybe String
    , domainName : String
    , path : String
    }

type alias MyNumber =
    Age