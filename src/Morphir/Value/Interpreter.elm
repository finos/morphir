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


{-| Evaluates a value expression recursively in a single pass while keeping track of variables and arguments along the
evaluation.
-}
evaluateValue : State -> Value () () -> Result Error (Value () ())
evaluateValue state value =
    case value of
        Value.Literal _ _ ->
            -- Literals cannot be evaluated any further
            Ok value

        Value.Tuple _ elems ->
            -- For a tuple we need to evaluate each element and return them wrapped back into a tuple
            elems
                -- We evaluate each element separately.
                |> List.map (evaluateValue state)
                -- If any of those fails we return the first failure.
                |> ListOfResults.liftFirstError
                -- If nothing fails we wrap the result in a tuple.
                |> Result.map (Value.Tuple ())

        Value.Variable _ varName ->
            -- When we run into a variable we simply look up the value of the variable in the state.
            state.variables
                |> Dict.get varName
                -- If we cannot find the variable ion the state we return an error.
                |> Result.fromMaybe (VariableNotFound varName)

        Value.Reference _ ((FQName packageName moduleName localName) as fQName) ->
            -- For references we first need to find what they point to.
            state.references
                |> Dict.get ( packageName, moduleName, localName )
                -- If the reference is not found we return an error.
                |> Result.fromMaybe (ReferenceNotFound fQName)
                -- If the reference is found we need to evaluate them.
                |> Result.andThen
                    (\reference ->
                        -- A reference can either point to a native function or another Morphir value.
                        case reference of
                            -- If it's a native function we invoke it directly.
                            NativeReference nativeFunction ->
                                nativeFunction
                                    (evaluateValue
                                        -- This is the state that will be used when native functions call "eval".
                                        -- We need to retain most of the current state but clear out the argument since
                                        -- the native function will evaluate completely new expressions.
                                        { state | argumentsReversed = [] }
                                    )
                                    -- Arguments are stored in reverse order in the state for efficiency so we need to
                                    -- flip them back to the original order.
                                    (List.reverse state.argumentsReversed)

                            -- If this is a reference to another Morphir value we need to recursively evaluate those.
                            ValueReference referredValue ->
                                evaluateValue state referredValue
                    )

        Value.Apply _ function argument ->
            -- When we run into an Apply we simply add the argument to the state and recursively evaluate the function.
            -- When there are multiple arguments there will be another Apply within the function so arguments will be
            -- repeatedly collected until we hit another node (lambda, reference or variable) where the arguments will
            -- be used to execute the calculation.
            evaluateValue
                { state
                    | argumentsReversed =
                        argument :: state.argumentsReversed
                }
                function

        Value.Lambda _ argumentPattern body ->
            -- By the time we run into a lambda we expect arguments to be available in the state.
            state.argumentsReversed
                -- So we start by taking the last argument in the state (We use head because the arguments are reversed).
                |> List.head
                -- If there are no arguments then our expression was invalid so we return an error.
                |> Result.fromMaybe NoArgumentToPass
                -- If the argument is available we first need to match it against the argument pattern.
                -- In Morhpir (just like in Elm) you can opattern-match on the argument of a lambda.
                |> Result.andThen
                    (\argumentValue ->
                        -- To match the pattern we call a helper function that both matches and extracts variables out
                        -- of the pattern.
                        evaluatePattern argumentPattern argumentValue
                            -- If the pattern does not match we error out. This should never happen with valid
                            -- expressions as lamdba argument patterns should only be used for decomposition not
                            -- filtering.
                            |> Result.mapError LambdaArgumentDidNotMatch
                    )
                -- Finally we evaluate the body of the lambda using the variables extracted by the pattern.
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
            Debug.todo "not implemented yet"


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
