module Morphir.Value.Error exposing (Error(..), PatternMismatch(..))

import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Value exposing (Pattern, RawValue, Value)


type Error
    = VariableNotFound Name
    | ReferenceNotFound FQName
    | NoArgumentToPassToLambda
    | LambdaArgumentDidNotMatch PatternMismatch
    | BindPatternDidNotMatch RawValue PatternMismatch
    | UnexpectedArguments (List RawValue)
    | ExpectedLiteral RawValue
    | ExpectedList RawValue
    | ExpectedTuple RawValue
    | ExpectedBoolLiteral RawValue
    | ExpectedIntLiteral RawValue
    | ExpectedFloatLiteral RawValue
    | ExpectedStringLiteral RawValue
    | ExpectedCharLiteral RawValue
    | ExpectedDecimalLiteral RawValue
    | ExpectedMaybe RawValue
    | ExpectedResult RawValue
    | IfThenElseConditionShouldEvaluateToBool RawValue RawValue
    | FieldNotFound RawValue Name
    | RecordExpected RawValue RawValue
    | NoPatternsMatch RawValue (List (Pattern ()))
    | ExactlyOneArgumentExpected (List RawValue)
    | ErrorWhileEvaluatingReference FQName Error
    | ErrorWhileEvaluatingVariable Name Error
    | TupleLengthNotMatchException (List RawValue) (List RawValue)
    | TupleExpected
    | NotImplemented


type PatternMismatch
    = PatternMismatch (Pattern ()) RawValue
