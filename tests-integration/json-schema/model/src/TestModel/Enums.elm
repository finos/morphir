module TestModel.Enums exposing (..)

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