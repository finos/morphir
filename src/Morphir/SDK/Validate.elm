module Morphir.SDK.Validate exposing (required, parse)

{-| This module provides convenient but unsafe operations that the tooling will translate into safe operation in the
runtime environment. Sample use:

    type alias Input =
        { name : Maybe String
        , age : String
        }

    type alias Validated =
        { name : String
        , age : Int
        }

    validate : Input -> Validated
    validate input =
        { name = required input.name
        , age = parse input.age
        }

@docs required, parse

-}

import Debug as HideDebug


{-| Indicate that a value is required without handling missing values.

    required (Just 1) == 1

    required Nothing -- compiles, runtime error in Elm

-}
required : Maybe a -> a
required maybe =
    case maybe of
        Just value ->
            value

        Nothing ->
            HideDebug.todo "Required value not available"


{-| Indicate that the String value should be parsed into a specific type without specifying how.

**Important:** running this in Elm will always fail!

    parse "11" + 2 -- compiles, runtime error in Elm

-}
parse : String -> a
parse string =
    HideDebug.todo
        (String.concat [ "Don't know how to parse '", string, "' into expected type" ])
