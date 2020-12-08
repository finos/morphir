module Morphir.Value.Interpreter exposing
    ( evaluate
    , FQN, Reference(..)
    )

{-| This module contains an interpreter for Morphir expressions. The interpreter takes a piece of logic as input,
evaluates it and returns the resulting data. In Morphir both logic and data is captured as a `Value` so the interpreter
takes a `Value` and returns a `Value` (or an error for invalid expressions):

@docs evaluate


# Utilities

@docs FQN, Reference

-}

import Dict exposing (Dict)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Path exposing (Path)
import Morphir.IR.Value as Value exposing (Pattern, Value)
import Morphir.ListOfResults as ListOfResults
import Morphir.Value.Error exposing (Error(..), PatternMismatch(..))
import Morphir.Value.Native as Native


{-| Represents a fully-qualified name. Same as [FQName](Morphir-IR-FQName#FQName) but comparable.
-}
type alias FQN =
    ( Path, Path, Name )


{-| Type used to keep track of the state of the evaluation. It contains:

  - References to other Morphir values or native functions.
  - The in-scope variables.
  - The arguments when we are processing an `Apply`. The arguments are in reverse order for efficiency.

-}
type alias State =
    { references : Dict FQN Reference
    , variables : Variables
    , argumentsReversed : List (Value () ())
    }


{-| Dictionary of variable name to value.
-}
type alias Variables =
    Dict Name (Value () ())


{-| Reference to an other value. The other value can either be another Morphir `Value` or a native function.
-}
type Reference
    = NativeReference Native.Function
    | ValueReference (Value () ())


{-| Evaluates a value expression and returns another value expression or an error. You can also pass in other values
by fully-qualified name that will be used for lookup if the expression contains references.

    evaluate
        SDK.nativeFunctions
        (Value.Apply ()
            (Value.Reference () (fqn "Morphir.SDK" "Basics" "not"))
            (Value.Literal () (BoolLiteral True))
        )
        -- (Value.Literal () (BoolLiteral False))

-}
evaluate : Dict FQN Reference -> Value () () -> Result Error (Value () ())
evaluate references value =
    let
        initialState : State
        initialState =
            State references Dict.empty []
    in
    evaluateValue initialState value


evaluateValue : State -> Value () () -> Result Error (Value () ())
evaluateValue state value =
    case value of
        Value.Variable _ varName ->
            state.variables
                |> Dict.get varName
                |> Result.fromMaybe (VariableNotFound varName)

        Value.Reference _ ((FQName packageName moduleName localName) as fQName) ->
            state.references
                |> Dict.get ( packageName, moduleName, localName )
                |> Result.fromMaybe (ReferenceNotFound fQName)
                |> Result.andThen
                    (\reference ->
                        case reference of
                            NativeReference nativeFunction ->
                                nativeFunction
                                    (evaluateValue
                                        -- This is the state that will be used when native functions call "eval".
                                        -- We need to retain most of the current state but clear out the argument since
                                        -- the native function will evaluate completely new expressions.
                                        { state | argumentsReversed = [] }
                                    )
                                    (List.reverse state.argumentsReversed)

                            ValueReference referredValue ->
                                evaluateValue state referredValue
                    )

        Value.Apply _ function argument ->
            evaluateValue
                { state
                    | argumentsReversed =
                        argument :: state.argumentsReversed
                }
                function

        Value.Lambda _ argumentPattern body ->
            state.argumentsReversed
                |> List.head
                |> Result.fromMaybe NoArgumentToPass
                |> Result.andThen
                    (\argumentValue ->
                        evaluatePattern argumentPattern argumentValue
                            |> Result.mapError LambdaArgumentDidNotMatch
                    )
                |> Result.andThen
                    (\argumentVariables ->
                        evaluateValue
                            { state
                                | variables =
                                    Dict.union argumentVariables state.variables
                            }
                            body
                    )

        _ ->
            Ok value


evaluatePattern : Pattern () -> Value () () -> Result PatternMismatch Variables
evaluatePattern pattern value =
    case pattern of
        Value.WildcardPattern _ ->
            Ok Dict.empty

        Value.AsPattern _ subjectPattern alias ->
            evaluatePattern subjectPattern value
                |> Result.map
                    (\subjectVariables ->
                        subjectVariables
                            |> Dict.insert alias value
                    )

        Value.TuplePattern _ elemPatterns ->
            case value of
                Value.Tuple _ elemValues ->
                    let
                        patternLength =
                            List.length elemPatterns

                        valueLength =
                            List.length elemValues
                    in
                    if patternLength == valueLength then
                        List.map2 evaluatePattern elemPatterns elemValues
                            |> ListOfResults.liftAllErrors
                            |> Result.mapError TupleMismatch
                            |> Result.map (List.foldl Dict.union Dict.empty)

                    else
                        Err (TupleElemCountMismatch patternLength valueLength)

                _ ->
                    Err (TupleExpected value)

        Value.ConstructorPattern _ ctorPatternFQName argPatterns ->
            let
                uncurry : Value ta va -> ( Value ta va, List (Value ta va) )
                uncurry v =
                    case v of
                        Value.Apply _ f a ->
                            let
                                ( nestedV, nestedArgs ) =
                                    uncurry f
                            in
                            ( nestedV, nestedArgs ++ [ a ] )

                        _ ->
                            ( v, [] )

                ( ctorValue, argValues ) =
                    uncurry value
            in
            case ctorValue of
                Value.Constructor _ ctorFQName ->
                    if ctorPatternFQName == ctorFQName then
                        let
                            patternLength =
                                List.length argPatterns

                            valueLength =
                                List.length argValues
                        in
                        if patternLength == valueLength then
                            List.map2 evaluatePattern argPatterns argValues
                                |> ListOfResults.liftAllErrors
                                |> Result.mapError ConstructorMismatch
                                |> Result.map (List.foldl Dict.union Dict.empty)

                        else
                            Err (ConstructorArgCountMismatch patternLength valueLength)

                    else
                        Err (ConstructorNameMismatch ctorPatternFQName ctorFQName)

                _ ->
                    Err (ConstructorExpected value)

        Value.EmptyListPattern _ ->
            case value of
                Value.List _ [] ->
                    Ok Dict.empty

                _ ->
                    Err (EmptyListExpected value)

        Value.HeadTailPattern _ headPattern tailPattern ->
            case value of
                Value.List a (headValue :: tailValue) ->
                    Result.map2 Dict.union
                        (evaluatePattern headPattern headValue)
                        (evaluatePattern tailPattern (Value.List a tailValue))

                _ ->
                    Err (NonEmptyListExpected value)

        Value.LiteralPattern _ matchLiteral ->
            case value of
                Value.Literal _ valueLiteral ->
                    if matchLiteral == valueLiteral then
                        Ok Dict.empty

                    else
                        Err (LiteralMismatch matchLiteral valueLiteral)

                _ ->
                    Err (LiteralExpected value)

        Value.UnitPattern _ ->
            case value of
                Value.Unit _ ->
                    Ok Dict.empty

                _ ->
                    Err (UnitExpected value)
