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


module Morphir.Rule exposing
    ( Rule
    , andThen, defaultToOriginal
    )

{-| Rules are partial functions (or `Pattern`s) that return the same type of value as what
they match on.

@docs Rule


# Working with rules

You can create a rule from a pattern simply by making sure that the return type is the same
as the type that is being matched (`Pattern a a`). If your pattern maps to a different type
you can map it back using `Pattern.map`:

@docs andThen, defaultToOriginal

-}

import Morphir.Pattern exposing (Pattern)


{-| Type that represents a rewrite rule which is a pattern that maps back to the same type.
-}
type alias Rule e a =
    Pattern a (Result e a)


{-| Chains two rules together.

    rule1 =
        Pattern.matchValue 1

    rule2 =
        Pattern.matchAny ->
            |> Pattern.map (\a -> a + 1)

    rule =
        rule1
            |> Rule.andThen rule2

    rule 1 == Just 2 -- rule1 matches and returns 1, rule2 matches and returns 1 + 1

    rule 2 == Nothing -- rule1 does not match

-}
andThen : (a -> Rule e a) -> Rule e a -> Rule e a
andThen f rule a =
    case rule a of
        Just (Ok firstRuleOut) ->
            f firstRuleOut a

        other ->
            other


{-| Turns a rule into a function that will return the original value when the rule doesn't match.

    rule =
        Pattern.matchValue 1
            |> Pattern.map (-)

    fun =
        rule
            |> Rule.defaultToOriginal

    fun 1 == -1 -- rule matches, mapped value returned

    fun 13 == 13 -- rule doesn't match, original value returned

-}
defaultToOriginal : Rule e a -> a -> Result e a
defaultToOriginal rule a =
    case rule a of
        Nothing ->
            Ok a

        Just result ->
            result
