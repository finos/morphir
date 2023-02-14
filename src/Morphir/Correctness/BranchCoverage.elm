module Morphir.Correctness.BranchCoverage exposing (..)

import Morphir.IR.Value as Value exposing (Pattern, Value)


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
    | PatternCondition (PatternConditionDetail va)


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
type alias PatternConditionDetail va =
    { excludes : List (Pattern va)
    , includes : Pattern va
    }


{-| Finds all the execution branches for a value expression. There is an additional flag to specify if boolean
expressions made up of multiple criteria (combined with or, and or not) should generate separate branches.
-}
valueBranches : Bool -> Value ta va -> List (Branch ta va)
valueBranches expandCriteria value =
    case value of
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
                                        { excludes = exclude
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
            -- a single branch with no conditions
            [ [] ]


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
                        (conditionBranches expandCriteria leftCondition False)
                        (conditionBranches expandCriteria rightCondition False)

            Value.Apply _ (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "or" ] )) leftCondition) rightCondition ->
                if expectedValue == True then
                    eitherBranches
                        (conditionBranches expandCriteria leftCondition True)
                        (conditionBranches expandCriteria rightCondition True)

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
eitherBranches : List (Branch ta va) -> List (Branch ta va) -> List (Branch ta va)
eitherBranches leftBranches rightBranches =
    leftBranches ++ rightBranches
