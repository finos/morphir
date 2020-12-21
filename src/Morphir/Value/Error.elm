module Morphir.Value.Error exposing (Error(..), PatternMismatch(..))

import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Literal exposing (Literal)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Value exposing (Pattern, Value)


type Error
    = VariableNotFound Name
    | ReferenceNotFound FQName
    | NoArgumentToPassToLambda
    | LambdaArgumentDidNotMatch PatternMismatch
    | BindPatternDidNotMatch (Value () ()) PatternMismatch
    | UnexpectedArguments (List (Value () ()))
    | ExpectedLiteral (Value () ())
    | ExpectedBoolLiteral Literal
    | IfThenElseConditionShouldEvaluateToBool (Value () ()) (Value () ())
    | FieldNotFound (Value () ()) Name
    | RecordExpected (Value () ()) (Value () ())
    | NoPatternsMatch (Value () ()) (List (Pattern ()))
    | ExactlyOneArgumentExpected (List (Value () ()))
    | ErrorWhileEvaluatingReference FQName Error
    | ErrorWhileEvaluatingVariable Name Error
    | ExpectedNumberTypeArguments (List (Value () ()))


type PatternMismatch
    = PatternMismatch (Pattern ()) (Value () ())
