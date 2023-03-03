module TestModel.OptionalTypes exposing (..)


type alias MaybeRep a =
    Maybe a


type alias FooBar =
    { foo : Maybe Float
    , bar : String
    }


type alias FooBarBaz =
    { foo : Int
    , bar : Float
    , baz : Maybe (Maybe String)
    }
