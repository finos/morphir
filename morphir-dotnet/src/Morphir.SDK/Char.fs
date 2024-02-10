module Morphir.SDK.Char

type Char = char

let inline isUpper (ch: Char) : bool = Char.IsUpper(ch)
let inline toUpper (ch: Char) : Char = Char.ToUpperInvariant(ch)