module Morphir.SDK.Char

type Char = char

let inline toUpper (ch: Char) : Char = Char.ToUpperInvariant(ch)
