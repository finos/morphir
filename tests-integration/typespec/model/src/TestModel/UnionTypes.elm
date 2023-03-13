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
