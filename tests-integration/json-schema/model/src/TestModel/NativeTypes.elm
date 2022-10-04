module TestModel.NativeTypes exposing (..)

import Morphir.SDK.Decimal exposing (Decimal)
import Morphir.SDK.LocalDate exposing (LocalDate)

type alias Employee
    = String


type alias TransactionDate
    = LocalDate

type alias TaxRate
    = Decimal

type alias Taj
    = Int
