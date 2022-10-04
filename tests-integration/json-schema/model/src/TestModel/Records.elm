module TestModel.Records exposing (..)

type alias Bank =
    { bankName : String
    , address : Address}

type alias Address =
    { country : String
    , state : String
    , street : String
    }