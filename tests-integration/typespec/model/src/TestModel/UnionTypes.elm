module TestModel.UnionTypes exposing (..)

import TestModel.AdvancedTypes exposing (DateOfBirth)


type FooBarBaz
    = Foo Int
    | Bar String
    | Baz Float


type Currency
    = USD
    | GBP
    | GHS


type Reference
    = Bar DateOfBirth


type Valu
    = Valu Int


type Value
    = Value Currency


type alias Name1 =
    String


type Name2
    = Name2 Name1


type Name3
    = Name3 Name2


type Name4
    = Name4 Name3
