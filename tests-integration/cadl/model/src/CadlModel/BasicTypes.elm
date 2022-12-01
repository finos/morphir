module CadlModel.BasicTypes exposing (..)

import Dict exposing (Dict)
import Set exposing (Set)


type alias BoolReap =
    Bool


type alias FloatRep =
    Float


type alias IntRep =
    Int


type alias StringRep =
    String


type alias CharRep =
    Char


type alias DecimalRep =
    String


type alias StringList =
    List String


type alias IntegerSetList =
    Set Int


type alias StringIntTuple =
    ( String, Int )


type alias SingleTypeArg a =
    a


type alias MultipleTypeArgs a b =
    ( a, b )


type alias OneArgList a =
    List a


type alias DictType a b =
    Dict a b


type alias ResultType a b =
    Result a b


type alias MaybeRep a =
    Maybe a


type alias FooBarBazRecord =
    { foo : Int
    , bar : String
    , baz : StringRep
    , baj : Maybe Int
    }
