[<AutoOpen>]
module Morphir.SDK.Comparison

/// Represents the relative ordering of two things.
/// The relations are less than, equal to, and greater than
type Order =
    | LT
    | EQ
    | GT

let inline lessThan x y = x < y

let inline greaterThan x y = x > y

let inline lessThanOrEqual x y = x <= y

let inline greaterThanOrEqual x y = x >= y

let inline max x y = Microsoft.FSharp.Core.Operators.max x y

let inline min x y = Microsoft.FSharp.Core.Operators.min x y
