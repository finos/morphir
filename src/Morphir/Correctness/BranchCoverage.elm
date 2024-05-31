module Morphir.Correctness.BranchCoverage exposing (..)

import Dict exposing (Dict)
import Morphir.Correctness.Test exposing (TestCase)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name exposing (Name)
import Morphir.IR.SDK as SDK
import Morphir.IR.Value as Value exposing (Pattern, RawValue, Value)
import Morphir.Value.Interpreter as Interpreter


{-| A branch of execution is defined as a list of conditions. The interpretation requires an additional expression tree
(`Value`). The branch is the path that the execution takes on that value when the conditions are met. For example
given the logic below:

    if a < b then
        if a < 0 then
            0

        else
            a

    else
        b

There are 3 branches:

  - [ a < b == True, a < 0 == True ]
  - [ a < b == True, a < 0 == False ]
  - [ a < b == False ]

-}
type alias Branch ta va =
    List (Condition ta va)


{-| Represents a condition that decides which execution path will be taken. It could either be a boolean expression or
a pattern.
-}
type Condition ta va
    = BoolCondition (BoolConditionDetail ta va)
    | PatternCondition (PatternConditionDetail ta va)


{-| Represents a boolean condition as criterion and expected value. For example, given the following logic:

    if a < 0 then
        1

    else
        2

There are two branches that each correspond to a single condition. Both conditions have the same criterion: `a < 0`.
The expected values will be different: true for the then branch and false for the else.

-}
type alias BoolConditionDetail ta va =
    { criterion : Value ta va
    , expectedValue : Bool
    }


{-| Represents a pattern condition as set of excluded and one included pattern. For example, given the following logic:

    case a of
        1 ->
            "foo"

        2 ->
            "bar"

        _ ->
            "baz"

There are 3 branches that each correspond to a single condition:

  - condition 1
      - excludes: empty list
      - includes: 1
  - condition 2
      - excludes: 1
      - includes: 2
  - condition 3
      - excludes: 1, 2
      - includes: \_

Accumulating the excluded patterns is necessary so that the resulting condition can be interpreted independently while
keeping the sequential semantics of the pattern match intact. In many cases the excludes list will be redundant but we
will always specify it so that it works consistently in every case.

-}
type alias PatternConditionDetail ta va =
    { subject : Value ta va
    , excludes : List (Pattern va)
    , includes : Pattern va
    }


{-| Finds all the execution branches for a value expression. There is an additional flag to specify if boolean
expressions made up of multiple criteria (combined with or, and or not) should generate separate branches.
-}
valueBranches : Bool -> Value ta va -> List (Branch ta va)
valueBranches expandCriteria value =
    value
        |> Value.reduceValueBottomUp
            (\currentValue childBranches ->
                case currentValue of
                    Value.IfThenElse _ cond thenBranch elseBranch ->
                        List.concat
                            [ bothBranches
                                (conditionBranches expandCriteria cond True)
                                (valueBranches expandCriteria thenBranch)
                            , bothBranches
                                (conditionBranches expandCriteria cond False)
                                (valueBranches expandCriteria elseBranch)
                            ]

                    Value.PatternMatch _ subject cases ->
                        let
                            caseBranches : List ( Pattern va, Value ta va ) -> List (Pattern va) -> List (Branch ta va)
                            caseBranches remainingCases exclude =
                                case remainingCases of
                                    ( nextCasePattern, nextCaseBody ) :: restOfCases ->
                                        let
                                            patternCondition : Condition ta va
                                            patternCondition =
                                                PatternCondition
                                                    { subject = subject
                                                    , excludes = exclude
                                                    , includes = nextCasePattern
                                                    }

                                            nextCaseBranches : List (Branch ta va)
                                            nextCaseBranches =
                                                bothBranches
                                                    [ [ patternCondition ] ]
                                                    (valueBranches expandCriteria nextCaseBody)
                                        in
                                        List.concat
                                            [ nextCaseBranches
                                            , caseBranches restOfCases (exclude ++ [ nextCasePattern ])
                                            ]

                                    [] ->
                                        []
                        in
                        bothBranches
                            (valueBranches expandCriteria subject)
                            (caseBranches cases [])

                    _ ->
                        if List.isEmpty childBranches then
                            -- a single branch with no conditions
                            [ [] ]

                        else
                            eitherBranches childBranches
            )


{-| Generates branches (combinations of conditions) that will make the condition passed in produce the expected value
that is also passed in. Arguments have the following meaning:

  - `expandCriteria` - when set to true boolean expressions with not, and, or will be split up into separate branches
  - `condition` - the expression to generate branches for
  - `expectedValue` - the value that the condition should return in this branch

In the general case it returns a single branch with the one condition that was passed in but when the `expandCriteria`
flag is passed in and the condition contains or, and or not operators the logic will remove them and return appropriate
branches as described below:

  - When a `not` is detected it will be removed and the expected value is negated.
  - When an `and` is detected it will be removed and depending on the expected value the following will be returned:
      - If the expected value is `true` then a cartesian product of branches where both sub-conditions are true will be
        returned.
      - If the expected value is `false` then the union of branches for sub-conditions will be returned.
  - When an `or` is detected it will be removed and depending on the expected value the following will be returned:
      - If the expected value is `true` then the union of branches for sub-conditions will be returned.
      - If the expected value is `false` then a cartesian product of branches where both sub-conditions are true will be
        returned.

-}
conditionBranches : Bool -> Value ta va -> Bool -> List (Branch ta va)
conditionBranches expandCriteria condition expectedValue =
    if expandCriteria then
        case condition of
            Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "not" ] )) nestedCondition ->
                conditionBranches expandCriteria nestedCondition (not expectedValue)

            Value.Apply _ (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "and" ] )) leftCondition) rightCondition ->
                if expectedValue == True then
                    bothBranches
                        (conditionBranches expandCriteria leftCondition True)
                        (conditionBranches expandCriteria rightCondition True)

                else
                    eitherBranches
                        [ bothBranches
                            (conditionBranches expandCriteria leftCondition True)
                            (conditionBranches expandCriteria rightCondition False)
                        , bothBranches
                            (conditionBranches expandCriteria leftCondition False)
                            (conditionBranches expandCriteria rightCondition True)
                        , bothBranches
                            (conditionBranches expandCriteria leftCondition False)
                            (conditionBranches expandCriteria rightCondition False)
                        ]

            Value.Apply _ (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "or" ] )) leftCondition) rightCondition ->
                if expectedValue == True then
                    eitherBranches
                        [ bothBranches
                            (conditionBranches expandCriteria leftCondition True)
                            (conditionBranches expandCriteria rightCondition False)
                        , bothBranches
                            (conditionBranches expandCriteria leftCondition False)
                            (conditionBranches expandCriteria rightCondition True)
                        , bothBranches
                            (conditionBranches expandCriteria leftCondition True)
                            (conditionBranches expandCriteria rightCondition True)
                        ]

                else
                    bothBranches
                        (conditionBranches expandCriteria leftCondition False)
                        (conditionBranches expandCriteria rightCondition False)

            _ ->
                [ [ BoolCondition
                        { criterion = condition
                        , expectedValue = expectedValue
                        }
                  ]
                ]

    else
        [ [ BoolCondition
                { criterion = condition
                , expectedValue = expectedValue
                }
          ]
        ]


{-| Utility to generate branches with conditions that satisfy both sides
-}
bothBranches : List (Branch ta va) -> List (Branch ta va) -> List (Branch ta va)
bothBranches leftBranches rightBranches =
    leftBranches
        |> List.concatMap
            (\leftBranch ->
                rightBranches
                    |> List.map
                        (\rightBranch ->
                            leftBranch ++ rightBranch
                        )
            )


{-| Utility to generate branches with conditions that satisfy either one or the other side
-}
eitherBranches : List (List (Branch ta va)) -> List (Branch ta va)
eitherBranches allBranches =
    List.concat allBranches


{-| Function that classifies test cases by branch coverage. It takes an IR, a function definition and a list of test
cases as an input and returns a list of branches and the test cases that cover that branch. If a certain branch is not
covered by a test the list will be empty.
-}
assignTestCasesToBranches : Distribution -> Value.Definition ta va -> List TestCase -> List ( Branch ta va, List TestCase )
assignTestCasesToBranches ir valueDef testCases =
    valueBranches True valueDef.body
        |> List.map
            (\branch ->
                ( branch
                , testCases
                    |> List.filter
                        (\testCase ->
                            let
                                variables : Dict Name RawValue
                                variables =
                                    List.map2
                                        (\( argName, _, _ ) maybeArgValue ->
                                            maybeArgValue
                                                |> Maybe.map (Tuple.pair argName)
                                        )
                                        valueDef.inputTypes
                                        testCase.inputs
                                        |> List.filterMap identity
                                        |> Dict.fromList

                                matchesConditions : List (Condition ta va) -> Bool
                                matchesConditions conditions =
                                    case conditions of
                                        [] ->
                                            True

                                        nextCondition :: restOfConditions ->
                                            case nextCondition of
                                                BoolCondition cond ->
                                                    let
                                                        rawCriterion : Value () ()
                                                        rawCriterion =
                                                            cond.criterion |> Value.mapValueAttributes (always ()) (always ())
                                                    in
                                                    case Interpreter.evaluateValue SDK.nativeFunctions ir variables [] rawCriterion of
                                                        Ok (Value.Literal _ (BoolLiteral actualResult)) ->
                                                            if cond.expectedValue == actualResult then
                                                                matchesConditions restOfConditions

                                                            else
                                                                False

                                                        _ ->
                                                            False

                                                PatternCondition cond ->
                                                    let
                                                        rawSubject : RawValue
                                                        rawSubject =
                                                            cond.subject |> Value.mapValueAttributes (always ()) (always ())

                                                        evaluatedSubject : RawValue
                                                        evaluatedSubject =
                                                            case Interpreter.evaluateValue SDK.nativeFunctions ir variables [] rawSubject of
                                                                Ok result ->
                                                                    result

                                                                Err _ ->
                                                                    Value.Unit ()

                                                        matches : Pattern va -> Bool
                                                        matches pattern =
                                                            case
                                                                Interpreter.matchPattern
                                                                    (pattern |> Value.mapPatternAttributes (always ()))
                                                                    evaluatedSubject
                                                            of
                                                                Ok _ ->
                                                                    True

                                                                _ ->
                                                                    False

                                                        matchesAny : List (Pattern va) -> Bool
                                                        matchesAny patterns =
                                                            case patterns of
                                                                [] ->
                                                                    False

                                                                nextPattern :: restOfPatterns ->
                                                                    if matches nextPattern then
                                                                        True

                                                                    else
                                                                        matchesAny restOfPatterns
                                                    in
                                                    if matches cond.includes then
                                                        matchesAny cond.excludes

                                                    else
                                                        False
                            in
                            matchesConditions branch
                        )
                )
            )
