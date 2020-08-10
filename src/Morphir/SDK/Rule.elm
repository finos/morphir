{-
Copyright 2020 Morgan Stanley

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}


module Morphir.SDK.Rule exposing
    ( Rule
    , chain
    , any, is, anyOf, noneOf
    )

{-| This module supports defining business logic as a set of rules. You can think of it as a functional rules engine.
The logic is built up of rules that are composed into rule sets. In traditional rules engines these rule sets can be
executed in a variety of ways that can yield different results. Morphir prefers predictability over flexibility so we
only support sequential execution. While this might sound limiting it greatly improves readability and enforces modelers
to break up large rule sets into smaller targeted ones.

@docs Rule

@docs chain

@docs any, is, anyOf, noneOf

-}


{-| Type that represents a single rule. A rule is a function that is only applicable on certain inputs. In other words
it's a partial-function. Since Elm/Morphir only supports total functions it is represented as a function that returns
an optional value. When the function is applicable it will return `Just b` otherwise `Nothing`.
-}
type alias Rule a b =
    a -> Maybe b


{-| Chain a list of rules into a single rule. Rules are evaluated sequentially in the order they were supplied and
the first rule that matches will be applied.

    myChain =
        chain
            [ \a -> Nothing -- A rule that never matches
            , \a -> Just a -- A rule that always matches and returns the original value
            ]

    myChain 42 == Just 42

-}
chain : List (Rule a b) -> Rule a b
chain rules input =
    case rules of
        [] ->
            Nothing

        firstRule :: restOfRules ->
            case firstRule input of
                Just result ->
                    Just result

                Nothing ->
                    chain restOfRules input


{-| Simply returns true for any input. Use as a wildcard in a decision table.
-}
any : a -> Bool
any =
    always True


{-| Returns `True` only if the second argument is equal to the first. Use in a decision table for exact match.
-}
is : a -> a -> Bool
is a1 a2 =
    a1 == a2


{-| Returns `True` only if the second argument can be found in the list specified in the first argument. Use in a
decision table to match when a value is in a predefined set.
-}
anyOf : List a -> a -> Bool
anyOf list a =
    List.member a list


{-| Returns `True` only if the second argument cannot be found in the list specified in the first argument. Use in a
decision table to match when a value is not in a predefined set.
-}
noneOf : List a -> a -> Bool
noneOf list a =
    not (anyOf list a)
