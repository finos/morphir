module Morphir.Value.Error exposing (..)

import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Literal exposing (Literal)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Value exposing (Pattern, Value)


type Error
    = VariableNotFound Name
    | ReferenceNotFound FQName
    | NoArgumentToPass
    | LambdaArgumentDidNotMatch PatternMismatch
    | UnexpectedArguments (List (Value () ()))
    | ExpectedLiteral (Value () ())
    | ExpectedBoolLiteral Literal
    | IfThenElseConditionShouldEvaluateToBool (Value () ()) (Value () ())
    | FieldNotFound (Value () ()) Name
    | RecordExpected (Value () ()) (Value () ())


type PatternMismatch
    = PatternMismatch (Pattern ()) (Value () ())
