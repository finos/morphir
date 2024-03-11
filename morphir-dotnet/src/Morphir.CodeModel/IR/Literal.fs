module Morphir.IR.Literal

open System
open Morphir

/// <summary>
/// Type that represents a literal value.
/// </summary>
type Literal =
    | BoolLiteral of Boolean
    | CharLiteral of Char
    | StringLiteral of String
    | WholeNumberLiteral of Int64
    | FloatLiteral of Double
    | DecimalLiteral of Decimal

let boolLiteral (value: bool) = BoolLiteral value

let charLiteral (value: char) = CharLiteral value

let stringLiteral (value: string) = StringLiteral value

let intLiteral value = WholeNumberLiteral value

let floatLiteral value = FloatLiteral value

let decimalLiteral value = DecimalLiteral value

let wholeNumberLiteral value = WholeNumberLiteral value

let toString =
    function
    | BoolLiteral value -> if value then "True" else "False"
    | CharLiteral value -> $"'{value}'"
    | StringLiteral value -> $"\"{value}\""
    | WholeNumberLiteral value -> value.ToString()
    | FloatLiteral value -> value.ToString()
    | DecimalLiteral value -> value.ToString()
