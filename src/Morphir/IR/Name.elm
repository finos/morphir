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


module Morphir.IR.Name exposing
    ( Name, fromList, toList
    , fromString, toTitleCase, toCamelCase, toSnakeCase, toHumanWords, toHumanWordsTitle
    )

{-| `Name` is an abstraction of human-readable identifiers made up of words. This abstraction
allows us to use the same identifiers across various naming conventions used by the different
frontend and backend languages Morphir integrates with.

    name = fromList [ "value", "in", "u", "s", "d" ]

    toTitleCase name --> "ValueInUSD"
    toCamelCase name --> "valueInUSD"
    toSnakeCase name --> "value_in_USD"


## Abbreviations

We frequently use abbreviations in a business context to be more concise.
From a naming perspective abbreviations are challanging because they are not real words and
behave slightly differently. In this module we treat abbreviations as a list of single-letter
words. This approach fits nicely into camel and title case naming conventions but when using
snake-case the direct translation would look unnatural:

    toSnakeCase name -- "value_in_u_s_d" ?

To resolve this and help creating human-readable strings we added functionality to turn
abbreviations into upper-case words. We treat any series of single letter words as an
abbreviation:

    toSnakeCase name --> "value_in_USD"

@docs Name, fromList, toList


# String conversion

@docs fromString, toTitleCase, toCamelCase, toSnakeCase, toHumanWords, toHumanWordsTitle

-}

import Regex exposing (Regex)


{-| Type that represents a name that is made up of words.
-}
type alias Name =
    List String


{-| Translate a string into a name by splitting it into words. The algorithm is designed
to work with most well-known naming conventions or mix of them. The general rule is that
consecutive letters and numbers are treated as words, upper-case letters and non-alphanumeric
characters start a new word.

    fromString "fooBar_baz 123"
    --> Name.fromList [ "foo", "bar", "baz", "123" ]

    fromString "valueInUSD"
    --> Name.fromList [ "value", "in", "u", "s", "d" ]

    fromString "ValueInUSD"
    --> Name.fromList [ "value", "in", "u", "s", "d" ]

    fromString "value_in_USD"
    --> Name.fromList [ "value", "in", "u", "s", "d" ]

    fromString "_-%"
    --> Name.fromList []

-}
fromString : String -> Name
fromString string =
    let
        wordPattern : Regex
        wordPattern =
            Regex.fromString "([a-zA-Z][a-z]*|[0-9]+)"
                |> Maybe.withDefault Regex.never
    in
    Regex.find wordPattern string
        |> List.map .match
        |> List.map String.toLower
        |> fromList


{-| Turns a name into a title-case string.

    toTitleCase (fromList [ "foo", "bar", "baz", "123" ])
    --> "FooBarBaz123"

    toTitleCase (fromList [ "value", "in", "u", "s", "d" ])
    --> "ValueInUSD"

-}
toTitleCase : Name -> String
toTitleCase name =
    name
        |> toList
        |> List.map capitalize
        |> String.join ""


{-| Turns a name into a camel-case string.

    toCamelCase (fromList [ "foo", "bar", "baz", "123" ])
    --> "fooBarBaz123"

    toCamelCase (fromList [ "value", "in", "u", "s", "d" ])
    --> "valueInUSD"

-}
toCamelCase : Name -> String
toCamelCase name =
    case name |> toList of
        [] ->
            ""

        head :: tail ->
            tail
                |> List.map capitalize
                |> (::) head
                |> String.join ""


{-| Turns a name into a snake-case string.

    toSnakeCase (fromList [ "foo", "bar", "baz", "123" ])
    --> "foo_bar_baz_123"

    toSnakeCase (fromList [ "value", "in", "u", "s", "d" ])
    --> "value_in_USD"

-}
toSnakeCase : Name -> String
toSnakeCase name =
    name
        |> toHumanWords
        |> String.join "_"


{-| Turns a name into a list of human-readable strings. The only difference
compared to [`toList`](#toList) is how it handles abbreviations. They will
be turned into a single upper-case word instead of separate single-character
words.

    toHumanWords (fromList [ "value", "in", "u", "s", "d" ])
    --> [ "value", "in", "USD" ]

-}
toHumanWords : Name -> List String
toHumanWords name =
    let
        words : List String
        words =
            toList name

        join : List String -> String
        join abbrev =
            abbrev
                |> String.join ""
                |> String.toUpper

        process : List String -> List String -> List String -> List String
        process prefix abbrev suffix =
            case suffix of
                [] ->
                    if List.isEmpty abbrev then
                        prefix

                    else
                        List.append prefix [ join abbrev ]

                first :: rest ->
                    if String.length first == 1 then
                        process prefix (List.append abbrev [ first ]) rest

                    else
                        case abbrev of
                            [] ->
                                process (List.append prefix [ first ]) [] rest

                            _ ->
                                process (List.append prefix [ join abbrev, first ]) [] rest
    in
    case name of
        [word] ->
            if String.length word == 1 then
                name
            else
                process [] [] words
        _ ->
            process [] [] words


{-| Turns a name into a list of human-readable strings with the first word capitalized. The only difference
compared to [`toList`](#toList) is how it handles abbreviations. They will
be turned into a single upper-case word instead of separate single-character
words.

    toHumanWordsTitle (fromList [ "value", "in", "u", "s", "d" ])
    --> [ "Value", "in", "USD" ]

-}
toHumanWordsTitle : Name -> List String
toHumanWordsTitle name =
    case toHumanWords name of
        firstWord :: rest ->
            capitalize firstWord :: rest

        [] ->
            []


capitalize : String -> String
capitalize string =
    case String.uncons string of
        Just ( headChar, tailString ) ->
            String.cons (Char.toUpper headChar) tailString

        Nothing ->
            string


{-| Convert a list of strings into a name.
-}
fromList : List String -> Name
fromList words =
    words


{-| Convert a name to a list of strings.
-}
toList : Name -> List String
toList words =
    words
