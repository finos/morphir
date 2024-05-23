module Morphir.Value.Error exposing (Error(..), PatternMismatch(..), toString)

import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Name exposing (Name, toCamelCase)
import Morphir.IR.Value as Value exposing (Pattern, RawValue, Value)


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
    | ExpectedDerivedType FQName RawValue
    | ExpectedUUID RawValue
    | IfThenElseConditionShouldEvaluateToBool RawValue RawValue
    | FieldNotFound RawValue Name
    | RecordExpected RawValue RawValue
    | NoPatternsMatch RawValue (List (Pattern ()))
    | ExactlyOneArgumentExpected (List RawValue)
    | ErrorWhileEvaluatingReference FQName Error
    | ErrorWhileEvaluatingDerivedType String
    | ErrorWhileEvaluatingVariable Name Error
    | TupleLengthNotMatchException (List RawValue) (List RawValue)
    | TupleExpected
    | NotImplemented


type PatternMismatch
    = PatternMismatch (Pattern ()) RawValue


toString : Error -> String
toString error =
    let
        differentValueExpected : String -> Value ta va -> String
        differentValueExpected expected got =
            "Expected a(n) " ++ expected ++ " instead of: " ++ Value.toString got
    in
    case error of
        VariableNotFound name ->
            "Variable " ++ toCamelCase name ++ " not found"

        ReferenceNotFound fqName ->
            "Could not find function reference: " ++ FQName.toString fqName

        NoArgumentToPassToLambda ->
            "The lambda function received no arguments"

        LambdaArgumentDidNotMatch _ ->
            "Lambda argument mismatch"

        BindPatternDidNotMatch _ _ ->
            "Bind argument mismatch"

        UnexpectedArguments argList ->
            "Unexpected arguments: " ++ String.concat (List.map (\arg -> Value.toString arg ++ ", ") argList)

        ExpectedLiteral val ->
            differentValueExpected "Literal" val

        ExpectedList val ->
            differentValueExpected "List" val

        ExpectedTuple val ->
            differentValueExpected "Tuple" val

        ExpectedBoolLiteral val ->
            differentValueExpected "Bool Literal" val

        ExpectedIntLiteral val ->
            differentValueExpected "Int Literal" val

        ExpectedFloatLiteral val ->
            differentValueExpected "Float Literal" val

        ExpectedStringLiteral val ->
            differentValueExpected "String Literal" val

        ExpectedCharLiteral val ->
            differentValueExpected "Char Literal" val

        ExpectedDecimalLiteral val ->
            differentValueExpected "Decimal Literal" val

        ExpectedMaybe val ->
            differentValueExpected "Maybe" val

        ExpectedResult val ->
            differentValueExpected "Result" val

        ExpectedDerivedType _ val ->
            differentValueExpected "Derived Type" val

        ExpectedUUID val ->
            differentValueExpected "UUID" val

        IfThenElseConditionShouldEvaluateToBool a b ->
            "The if-then-else condition " ++ Value.toString a ++ " should evaluate to True/False instead of " ++ Value.toString b

        FieldNotFound rec fieldName ->
            "Field " ++ toCamelCase fieldName ++ " on record " ++ Value.toString rec ++ " not found"

        RecordExpected _ val ->
            differentValueExpected "Record" val

        NoPatternsMatch _ _ ->
            "No patterns match"

        ExactlyOneArgumentExpected argList ->
            "Exactly one argument expected, but got multiple: " ++ String.concat (List.map (\arg -> Value.toString arg ++ ", ") argList)

        ErrorWhileEvaluatingReference fqName e ->
            "Error while evaluating reference " ++ FQName.toString fqName ++ " : " ++ toString e

        ErrorWhileEvaluatingDerivedType s ->
            "Error while evaluating derived type: " ++ s

        ErrorWhileEvaluatingVariable varName e ->
            "Error while evaluating variable " ++ toCamelCase varName ++ " : " ++ toString e

        TupleLengthNotMatchException _ _ ->
            "Tuple lenghts do not match"

        TupleExpected ->
            "Expected a Tuple"

        NotImplemented ->
            "Not Implemented"
