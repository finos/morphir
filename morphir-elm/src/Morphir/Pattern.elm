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


module Morphir.Pattern exposing
    ( Pattern
    , matchAny, matchValue
    , matchList
    , map
    )

{-| This module contains tools for enhanced pattern-matching.


# Pattern Combinators

Elm has built-in pattern-matching support but it has some limitations:

  - patterns can only be used within a case expression and patterns need
    to be exhaustive so you cannot define a single pattern in isolation
  - patterns can only be composed within a case expression so you cannot
    reuse complex patterns across different functions or modules

Fortunately it's relatively easy to get around this and provide a convenient
API that addresses those limitations. The key is to recognise that patterns
are partial functions which can be modeled as a function `a -> Maybe b` in Elm.

@docs Pattern

Using this approach we can create a pattern combinator library that allows
us to compose larger patterns from smaller ones and capture the result in a
stand-alone function that can be reused anywhere.

The process starts by defining some basic functions that allows us to match
the leaves in a pattern:

@docs matchAny, matchValue

Then we can move up a level and use combinators to build more complex patterns.
We provide some standard combinators for some types in `elm/core` here and
provide combinators for specific types in the module where the type is defined.

**Note**: Pattern combinators will always start with the word `match` so you
can search for the available combinators using that.

@docs matchList


## Other tools

@docs map

-}


{-| Type that represents a pattern which is just a partial-function.
-}
type alias Pattern a b =
    a -> Maybe b


{-| Create a new pattern by applying a function to the pattern's result.

    (matchAny |> map not) True == Just False

-}
map : (b -> c) -> Pattern a b -> Pattern a c
map f pattern a =
    pattern a
        |> Maybe.map f


{-| Matches any value and returns the value itself.

    matchAny 13 == Just 13

    matchAny True == Just True

-}
matchAny : Pattern a a
matchAny a =
    Just a


{-| Matches a specific value using `==` and returns the value itself when there is a match.

    match13 =
        matchValue 13

    match13 13 == Just 13
    match13 12 == Nothing

    matchTrue =
         matchValue True

    matchTrue True == Just True
    matchTrue False == Nothing

-}
matchValue : a -> Pattern a a
matchValue a b =
    if a == b then
        Just a

    else
        Nothing


{-| Matches an optional value against a pattern when the value is set and returns the value.

    matchJust13 =
        matchJust (matchValue 13)

    matchJust13 (Just 13) == Just 13
    matchJust13 (Just 14) == Nothing
    matchJust13 Nothing == Nothing

-}
matchJust : (a -> Maybe b) -> Pattern (Maybe a) b
matchJust f a =
    case a of
        Just v ->
            f v

        Nothing ->
            Nothing


{-| Matches a list of values using a list of patterns and returns the list of values extracted
by each pattern. It returns `Nothing` if the length of the list being matched doesn't equal the
number of patterns specified.

    matchListOfTwoValues =
        matchList [ matchAny, matchAny ]

    matchListOfTwoValues [ 1, 2 ] == Just [ 1, 2 ]
    matchListOfTwoValues [ 1, 2, 3 ] == Nothing
    matchListOfTwoValues [ True, False ] == Just [ True, False ]

    matchListOfTwoBoolsWhereFirstTrue =
        matchList [ matchValue True, matchAny ]

    matchListOfTwoBoolsWhereFirstTrue [ True, True ] == Just [ True, True ]
    matchListOfTwoBoolsWhereFirstTrue [ True, False ] == Just [ True, False ]
    matchListOfTwoBoolsWhereFirstTrue [ False, False ] == Nothing

-}
matchList : List (a -> Maybe b) -> Pattern (List a) (List b)
matchList matchItems listToMatch =
    if List.length matchItems == List.length listToMatch then
        let
            matchingItems : List (Maybe b)
            matchingItems =
                List.map2 (\matchItem item -> matchItem item)
                    matchItems
                    listToMatch
        in
        if matchingItems |> List.any (\x -> x == Nothing) then
            Nothing

        else
            Just (matchingItems |> List.filterMap identity)

    else
        Nothing
