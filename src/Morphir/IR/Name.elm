module Morphir.IR.Name exposing
    ( Name, fromList, toList
    , fromString, toTitleCase, toCamelCase, toSnakeCase, toHumanWords
    , fuzzName
    , encodeName, decodeName
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

@docs fromString, toTitleCase, toCamelCase, toSnakeCase, toHumanWords


# Property Testing

@docs fuzzName


# Serialization

@docs encodeName, decodeName

-}

import Fuzz exposing (Fuzzer)
import Json.Decode as Decode
import Json.Encode as Encode
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
        words =
            toList name

        join abbrev =
            abbrev
                |> String.join ""
                |> String.toUpper

        process prefix abbrev suffix =
            case suffix of
                [] ->
                    if List.isEmpty abbrev then
                        prefix

                    else
                        prefix ++ [ join abbrev ]

                first :: rest ->
                    if String.length first == 1 then
                        process prefix (abbrev ++ [ first ]) rest

                    else
                        case abbrev of
                            [] ->
                                process (prefix ++ [ first ]) [] rest

                            _ ->
                                process (prefix ++ [ join abbrev, first ]) [] rest
    in
    process [] [] words


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


{-| Name fuzzer.
-}
fuzzName : Fuzzer Name
fuzzName =
    let
        nouns =
            [ "area"
            , "benchmark"
            , "book"
            , "business"
            , "company"
            , "country"
            , "currency"
            , "day"
            , "description"
            , "entity"
            , "fact"
            , "family"
            , "from"
            , "government"
            , "group"
            , "home"
            , "id"
            , "job"
            , "left"
            , "lot"
            , "market"
            , "minute"
            , "money"
            , "month"
            , "name"
            , "number"
            , "owner"
            , "parent"
            , "part"
            , "problem"
            , "rate"
            , "right"
            , "state"
            , "source"
            , "system"
            , "time"
            , "title"
            , "to"
            , "valid"
            , "week"
            , "work"
            , "world"
            , "year"
            ]

        fuzzWord =
            nouns
                |> List.map Fuzz.constant
                |> Fuzz.oneOf
    in
    Fuzz.list fuzzWord
        |> Fuzz.map (List.take 3)
        |> Fuzz.map fromList


{-| Encode a name to JSON.
-}
encodeName : Name -> Encode.Value
encodeName name =
    name
        |> toList
        |> Encode.list Encode.string


{-| Decode a name from JSON.
-}
decodeName : Decode.Decoder Name
decodeName =
    Decode.list Decode.string
        |> Decode.map fromList
