module Morphir.SDK.Bool

type Bool = bool

let True = true
let False = false

/// Negate a boolean value.
let inline not value = FSharp.Core.Operators.not value

type System.Boolean with

    static member And(lValue, rValue) =
        lValue
        && rValue

let inline toString (bool: Bool) = bool.ToString()
