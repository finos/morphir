module Morphir.SDK.Decimal

open Morphir.SDK.Maybe

let fromString (s: string) : Maybe<decimal> =
    match System.Decimal.TryParse(s) with
    | (true, d) -> Just d
    | _ -> Nothing

let toString (d: decimal) : string = d.ToString()
