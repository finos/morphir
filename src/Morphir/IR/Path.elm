module Morphir.IR.Path exposing
    ( Path, fromList, toList
    , fromString, toString
    , isPrefixOf
    , fuzzPath
    , encodePath, decodePath
    )

{-| `Path` is a list of names that represents a path in the tree. It's used at various
places in the IR to identify types and values.

@docs Path, fromList, toList


# String conversion

@docs fromString, toString


# Utilities

@docs isPrefixOf


# Property Testing

@docs fuzzPath


# Serialization

@docs encodePath, decodePath

-}

import Fuzz exposing (Fuzzer)
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.Name as Name exposing (Name, decodeName, encodeName, fuzzName)
import Regex exposing (Regex)


{-| Type that represents a path as a list of names.
-}
type alias Path =
    List Name


{-| Translates a string into a path by splitting it into names along special characters.
The algorithm will treat any non-word charaters that are not spaces as a path separator.

    fromString "fooBar.Baz"
    --> Path.fromList
    -->     [ Name.fromList [ "foo", "bar" ]
    -->     , Name.fromList [ "baz" ]
    -->     ]

    fromString "foo bar/baz"
    --> Path.fromList
    -->     [ Name.fromList [ "foo", "bar" ]
    -->     , Name.fromList [ "baz" ]
    -->     ]

-}
fromString : String -> Path
fromString string =
    let
        separatorRegex : Regex
        separatorRegex =
            Regex.fromString "[^\\w\\s]+"
                |> Maybe.withDefault Regex.never
    in
    Regex.split separatorRegex string
        |> List.map Name.fromString
        |> fromList


{-| Turn a path into a string using the specified naming convention and separator.

    path =
        Path.fromList
            [ Name.fromList [ "foo", "bar" ]
            , Name.fromList [ "baz" ]
            ]

    toString Name.toTitleCase "." path
    --> "FooBar.Baz"

    toString Name.toSnakeCase "/" path
    --> "foo_bar/baz"

-}
toString : (Name -> String) -> String -> Path -> String
toString nameToString sep path =
    path
        |> toList
        |> List.map nameToString
        |> String.join sep


{-| Converts a list of names to a path.
-}
fromList : List Name -> Path
fromList names =
    names


{-| Converts a path to a list of names.
-}
toList : Path -> List Name
toList names =
    names


{-| Checks if a path is a prefix of another.

    isPrefixOf [ ["foo"], ["bar"] ] [ ["foo"] ] == True

    isPrefixOf [ ["foo"] ] [ ["foo"], ["bar"] ] == False

    isPrefixOf [ ["foo"], ["bar"] ] [ ["foo"], ["bar"] ] == True

-}
isPrefixOf : Path -> Path -> Bool
isPrefixOf path prefix =
    case ( prefix, path ) of
        -- empty path is a prefix of any other path
        ( [], _ ) ->
            True

        -- empty path has no prefixes except the empty prefix captured above
        ( _, [] ) ->
            False

        -- for any other case compare the head and recurse
        ( prefixHead :: prefixTail, pathHead :: pathTail ) ->
            if prefixHead == pathHead then
                isPrefixOf prefixTail pathTail

            else
                False


{-| Path fuzzer.
-}
fuzzPath : Fuzzer Path
fuzzPath =
    Fuzz.list fuzzName
        |> Fuzz.map (List.take 3)
        |> Fuzz.map fromList


{-| Encode a path to JSON.
-}
encodePath : Path -> Encode.Value
encodePath path =
    path
        |> toList
        |> Encode.list encodeName


{-| Decode a path from JSON.
-}
decodePath : Decode.Decoder Path
decodePath =
    Decode.list decodeName
        |> Decode.map fromList
