module TestModel.CustomTypes exposing (..)

import TestModel.AdvancedTypes exposing (Score)
import Morphir.SDK.LocalDate exposing (Month)


type PersonalData
    = Bio String Score


type Employee
    = Fulltime String


type Person
    = Adult String
    | Child String Int
    | Infant (List Month)


type Currencies
    = USD
    | NGN
    | HUF
    | EUR
    | JPY


type TransactionType
    = Commit String
    | Rollback String
    | SavePoint Int


type ObjectType
    = Procedure
    | View
    | StoredFunction
