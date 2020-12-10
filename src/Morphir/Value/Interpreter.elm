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
import Morphir.IR.Literal exposing (Literal(..))
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

        Value.Constructor _ _ ->
            -- Constructor cannot be evaluated any further
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

        Value.List _ items ->
            -- For a list we need to evaluate each element and return them wrapped back into a list
            items
                -- We evaluate each element separately.
                |> List.map (evaluateValue state)
                -- If any of those fails we return the first failure.
                |> ListOfResults.liftFirstError
                -- If nothing fails we wrap the result in a list.
                |> Result.map (Value.List ())

        Value.Record _ fields ->
            -- For a record we need to evaluate each element and return them wrapped back into a record
            fields
                -- We evaluate each field separately.
                |> List.map
                    (\( fieldName, fieldValue ) ->
                        evaluateValue state fieldValue
                            |> Result.map (Tuple.pair fieldName)
                    )
                -- If any of those fails we return the first failure.
                |> ListOfResults.liftFirstError
                -- If nothing fails we wrap the result in a record.
                |> Result.map (Value.Record ())

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

        Value.Field _ subjectValue fieldName ->
            -- Field selection is evaluated by evaluating the subject first then matching on the resulting record and
            -- getting the field with the specified name.
            evaluateValue state subjectValue
                |> Result.andThen
                    (\evaluatedSubjectValue ->
                        case evaluatedSubjectValue of
                            Value.Record _ fields ->
                                fields
                                    |> Dict.fromList
                                    |> Dict.get fieldName
                                    |> Result.fromMaybe (FieldNotFound subjectValue fieldName)

                            _ ->
                                Err (RecordExpected subjectValue evaluatedSubjectValue)
                    )

        Value.FieldFunction _ fieldName ->
            -- A field function expects exactly one argument to be passed through the state as subject value. Otherwise
            -- it behaves exactly like a `Field` expression.
            case state.argumentsReversed of
                [ subjectValue ] ->
                    evaluateValue { state | argumentsReversed = [] } subjectValue
                        |> Result.andThen
                            (\evaluatedSubjectValue ->
                                case evaluatedSubjectValue of
                                    Value.Record _ fields ->
                                        fields
                                            |> Dict.fromList
                                            |> Dict.get fieldName
                                            |> Result.fromMaybe (FieldNotFound subjectValue fieldName)

                                    _ ->
                                        Err (RecordExpected subjectValue evaluatedSubjectValue)
                            )

                other ->
                    Err (ExactlyOneArgumentExpected other)

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
                        matchPattern argumentPattern argumentValue
                            -- If the pattern does not match we error out. This should never happen with valid
                            -- expressions as lambda argument patterns should only be used for decomposition not
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

        Value.LetDefinition _ defName def inValue ->
            -- We evaluate a let definition by first evaluating the definition, then assigning it to the variable name
            -- given in `defName`. Finally we evaluate the `inValue` passing in the new variable in the state.
            evaluateValue state (Value.definitionToValue def)
                |> Result.andThen
                    (\defValue ->
                        evaluateValue
                            { state
                                | variables =
                                    state.variables
                                        |> Dict.insert defName defValue
                            }
                            inValue
                    )

        Value.LetRecursion va defs inValue ->
            Debug.todo "implement"

        Value.Destructure _ bindPattern bindValue inValue ->
            -- A destructure can be evaluated by evaluating the bind value, matching it against the bind pattern and
            -- finally evaluating the in value using the variables from the bind pattern.
            evaluateValue state bindValue
                |> Result.andThen (matchPattern bindPattern)
                |> Result.mapError (BindPatternDidNotMatch bindValue)
                |> Result.andThen
                    (\bindVariables ->
                        evaluateValue
                            { state
                                | variables = Dict.union bindVariables state.variables
                            }
                            inValue
                    )

        Value.IfThenElse _ condition thenBranch elseBranch ->
            -- If then else evaluation is trivial: you evaluate the condition and depending on the result you evaluate
            -- one of the branches
            evaluateValue state condition
                |> Result.andThen
                    (\conditionValue ->
                        case conditionValue of
                            Value.Literal _ (BoolLiteral conditionTrue) ->
                                let
                                    branchToFollow : Value () ()
                                    branchToFollow =
                                        if conditionTrue then
                                            thenBranch

                                        else
                                            elseBranch
                                in
                                evaluateValue state branchToFollow

                            _ ->
                                Err (IfThenElseConditionShouldEvaluateToBool condition conditionValue)
                    )

        Value.PatternMatch _ subjectValue cases ->
            -- For a pattern match we first need to evaluate the subject value then step through th cases, match
            -- each pattern until we find a matching case and when we do evaluate the body
            let
                findMatch : List ( Pattern (), Value () () ) -> Value () () -> Result Error (Value () ())
                findMatch remainingCases evaluatedSubject =
                    case remainingCases of
                        ( nextPattern, nextBody ) :: restOfCases ->
                            case matchPattern nextPattern evaluatedSubject of
                                Ok patternVariables ->
                                    evaluateValue
                                        { state | variables = Dict.union patternVariables state.variables }
                                        nextBody

                                Err _ ->
                                    findMatch restOfCases evaluatedSubject

                        [] ->
                            Err (NoPatternsMatch evaluatedSubject (cases |> List.map Tuple.first))
            in
            evaluateValue state subjectValue
                |> Result.andThen (findMatch cases)

        Value.UpdateRecord _ subjectValue fieldUpdates ->
            -- To update a record first we need to evaluate the subject value, then extract the record fields and
            -- finally replace all updated fields with the new values
            evaluateValue state subjectValue
                |> Result.andThen
                    (\evaluatedSubjectValue ->
                        case evaluatedSubjectValue of
                            Value.Record _ fields ->
                                -- Once we hve the fields we fold through the field updates
                                fieldUpdates
                                    |> List.foldl
                                        -- For each field update we update a single field and return the new field dictionary
                                        (\( fieldName, newFieldValue ) fieldsResultSoFar ->
                                            fieldsResultSoFar
                                                |> Result.andThen
                                                    (\fieldsSoFar ->
                                                        -- Before we update the field we check if it exists. We do not
                                                        -- want to create new fields as part of an update.
                                                        fieldsSoFar
                                                            |> Dict.get fieldName
                                                            |> Result.fromMaybe (FieldNotFound subjectValue fieldName)
                                                            |> Result.andThen
                                                                (\_ ->
                                                                    -- Before we replace the field value we need to
                                                                    -- evaluate the updated value.
                                                                    evaluateValue newFieldValue
                                                                        |> Result.map
                                                                            (\evaluatedNewFieldValue ->
                                                                                fieldsSoFar
                                                                                    |> Dict.insert
                                                                                        fieldName
                                                                                        evaluatedNewFieldValue
                                                                            )
                                                                )
                                                    )
                                        )
                                        -- We start with the original fields
                                        (Ok (fields |> Dict.fromList))
                                    |> Result.map (Dict.toList >> Value.Record ())

                            _ ->
                                Err (RecordExpected subjectValue evaluatedSubjectValue)
                    )

        Value.Unit _ ->
            -- Unit cannot be evaluated any further
            Ok value


{-| Matches a value against a pattern recursively. It either returns an error if there is a mismatch or a dictionary of
variable names to values extracted out of the pattern.
-}
matchPattern : Pattern () -> Value () () -> Result PatternMismatch Variables
matchPattern pattern value =
    let
        error : Result PatternMismatch Variables
        error =
            Err (PatternMismatch pattern value)
    in
    case pattern of
        Value.WildcardPattern _ ->
            -- Wildcard patterns will always succeed and produce any variables
            Ok Dict.empty

        Value.AsPattern _ subjectPattern alias ->
            -- As patterns always succeed and will assign the alias as variable name to the value passed in
            matchPattern subjectPattern value
                |> Result.map
                    (\subjectVariables ->
                        subjectVariables
                            |> Dict.insert alias value
                    )

        Value.TuplePattern _ elemPatterns ->
            case value of
                -- A tuple pattern only matches on tuples
                Value.Tuple _ elemValues ->
                    let
                        patternLength =
                            List.length elemPatterns

                        valueLength =
                            List.length elemValues
                    in
                    -- The number of elements in the pattern and the value have to match
                    if patternLength == valueLength then
                        -- We recursively match each element
                        List.map2 matchPattern elemPatterns elemValues
                            -- If there is a mismatch we return the first error
                            |> ListOfResults.liftFirstError
                            -- If the match is successful we union the variables returned
                            |> Result.map (List.foldl Dict.union Dict.empty)

                    else
                        error

                _ ->
                    error

        Value.ConstructorPattern _ ctorPatternFQName argPatterns ->
            -- When we match on a constructor pattern we need to match the constructor name and all the arguments
            let
                -- Constructor invocations are curried (wrapped into Apply as many times as many arguments there are)
                -- so we need to uncurry them before matching. Constructor matches on the other hand are not curried
                -- since it's not allowed to partially apply them in a pattern.
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
                    -- We first check the constructor name
                    if ctorPatternFQName == ctorFQName then
                        let
                            patternLength =
                                List.length argPatterns

                            valueLength =
                                List.length argValues
                        in
                        -- Then the arguments
                        if patternLength == valueLength then
                            List.map2 matchPattern argPatterns argValues
                                |> ListOfResults.liftFirstError
                                |> Result.map (List.foldl Dict.union Dict.empty)

                        else
                            error

                    else
                        error

                _ ->
                    error

        Value.EmptyListPattern _ ->
            -- Empty list pattern only matches on empty lists and does not produce variables
            case value of
                Value.List _ [] ->
                    Ok Dict.empty

                _ ->
                    error

        Value.HeadTailPattern _ headPattern tailPattern ->
            -- Head-tail pattern matches on any list with at least one element
            case value of
                Value.List a (headValue :: tailValue) ->
                    -- We recursively apply the head and tail patterns and union the resulting variables
                    Result.map2 Dict.union
                        (matchPattern headPattern headValue)
                        (matchPattern tailPattern (Value.List a tailValue))

                _ ->
                    error

        Value.LiteralPattern _ matchLiteral ->
            -- Literal matches simply do an exact match on the value and don't produce any variables
            case value of
                Value.Literal _ valueLiteral ->
                    if matchLiteral == valueLiteral then
                        Ok Dict.empty

                    else
                        error

                _ ->
                    error

        Value.UnitPattern _ ->
            -- Unit pattern only matches on unit and does not produce any variables
            case value of
                Value.Unit _ ->
                    Ok Dict.empty

                _ ->
                    error
