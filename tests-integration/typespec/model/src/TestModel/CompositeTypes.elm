module TestModel.CompositeTypes exposing (..)


type alias StringIntTuple =
    ( Int, String )


type alias MultipleTypeArgs a b =
    ( a, b )


type alias ResultType e v =
    Result e v


type alias FooBar =
    { foo : Int
    , bar : String
    }
