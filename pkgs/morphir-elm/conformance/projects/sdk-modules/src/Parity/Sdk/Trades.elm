module Parity.Sdk.Trades exposing (Trade, settle, total)

{-| Morphir SDK types in signatures. -}

import Morphir.SDK.Decimal as Decimal exposing (Decimal)
import Morphir.SDK.LocalDate exposing (LocalDate)


type alias Trade =
    { amount : Decimal
    , tradeDate : LocalDate
    , settleDate : Maybe LocalDate
    }


settle : Trade -> LocalDate
settle trade =
    trade.tradeDate


total : Decimal -> Decimal -> Decimal
total a b =
    Decimal.add a b


dates : List Trade -> List LocalDate
dates trades =
    List.map .tradeDate trades
