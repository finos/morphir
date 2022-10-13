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
    = Deposit
    | Withdrawal
    | Payment


type CustomerType
    = Individual
    | Corporate
    | Government
    | VIP
