module TestModel.CustomTypes exposing (..)


type FullName
    = Firstname


type Employee
    = Fulltime String


type Person
    = Adult String
    | Child String Int


type Currencies
    = USD
    | NGN
    | HUF
    | EUR
    | JPY


type TransactionType
    = Commit
    | Rollback
    | SavePoint


type ObjectType
    = Procedure
    | View
    | StoredFunction
