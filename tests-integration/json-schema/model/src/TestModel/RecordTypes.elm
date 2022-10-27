module TestModel.RecordTypes exposing (..)


type alias Resource =
    { resourceName : String
    , address : Address
    }


type alias Address =
    { protocol : String
    , domainName : String
    , path : String
    }
