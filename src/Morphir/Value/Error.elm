module Morphir.Value.Error exposing (..)

import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Literal exposing (Literal)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Value exposing (Value)


type Error
    = VariableNotFound Name
    | ReferenceNotFound FQName
    | NoArgumentToPass
    | LambdaArgumentDidNotMatch PatternMismatch
    | UnexpectedArguments (List (Value () ()))
    | ExpectedLiteral (Value () ())
    | ExpectedBoolLiteral Literal


type PatternMismatch
    = TupleElemCountMismatch Int Int
    | TupleExpected (Value () ())
    | TupleMismatch (List PatternMismatch)
    | ConstructorArgCountMismatch Int Int
    | ConstructorNameMismatch FQName FQName
    | ConstructorExpected (Value () ())
    | ConstructorMismatch (List PatternMismatch)
    | EmptyListExpected (Value () ())
    | NonEmptyListExpected (Value () ())
    | LiteralMismatch Literal Literal
    | LiteralExpected (Value () ())
    | UnitExpected (Value () ())
