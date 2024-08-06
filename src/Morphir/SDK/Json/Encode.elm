module Morphir.SDK.Json.Encode exposing
    ( encode, Value
    , string, int, float, bool, null
    , list, set
    , object, dict
    , localTime, maybe
    )

{-| Library for turning values into Json values.


# Encoding

@docs encode, Value


# Primitives

@docs string, int, float, bool, null


# Arrays

@docs list, set


# Objects

@docs object, dict


# Extra

@docs localTime, maybe

-}

import Dict exposing (Dict)
import Json.Encode as JE
import Json.Encode.Extra as JEE
import Morphir.SDK.LocalTime exposing (LocalTime)
import Set exposing (Set)



-- ENCODE


{-| Represents a JavaScript value.
-}
type alias Value =
    JE.Value


{-| Convert a `Value` into a prettified string. The first argument specifies
the amount of indentation in the resulting string.

    import JE as Encode

    tom : Encode.Value
    tom =
        Encode.object
            [ ( "name", Encode.string "Tom" )
            , ( "age", Encode.int 42 )
            ]

    compact =
        Encode.encode 0 tom

    -- {"name":"Tom","age":42}
    readable =
        Encode.encode 4 tom

    -- {
    --     "name": "Tom",
    --     "age": 42
    -- }

-}
encode : Int -> Value -> String
encode =
    JE.encode



-- PRIMITIVES


{-| Turn a `String` into a JSON string.

    import JE exposing (encode, string)


    -- encode 0 (string "")      == "\"\""
    -- encode 0 (string "abc")   == "\"abc\""
    -- encode 0 (string "hello") == "\"hello\""

-}
string : String -> Value
string =
    JE.string


{-| Turn an `Int` into a JSON number.

    import JE exposing (encode, int)


    -- encode 0 (int 42) == "42"
    -- encode 0 (int -7) == "-7"
    -- encode 0 (int 0)  == "0"

-}
int : Int -> Value
int =
    JE.int


{-| Turn a `Float` into a JSON number.

    import JE exposing (encode, float)


    -- encode 0 (float 3.14)     == "3.14"
    -- encode 0 (float 1.618)    == "1.618"
    -- encode 0 (float -42)      == "-42"
    -- encode 0 (float NaN)      == "null"
    -- encode 0 (float Infinity) == "null"

**Note:** Floating point numbers are defined in the [IEEE 754 standard][ieee]
which is hardcoded into almost all CPUs. This standard allows `Infinity` and
`NaN`. [The JSON spec][json] does not include these values, so we encode them
both as `null`.

[ieee]: https://en.wikipedia.org/wiki/IEEE_754
[json]: https://www.json.org/

-}
float : Float -> Value
float =
    JE.float


{-| Turn a `Bool` into a JSON boolean.

    import JE exposing (bool, encode)


    -- encode 0 (bool True)  == "true"
    -- encode 0 (bool False) == "false"

-}
bool : Bool -> Value
bool =
    JE.bool



-- NULLS


{-| Create a JSON `null` value.

    import JE exposing (encode, null)


    -- encode 0 null == "null"

-}
null : Value
null =
    JE.null



-- ARRAYS


{-| Turn a `List` into a JSON array.

    import JE as Encode exposing (bool, encode, int, list, string)


    -- encode 0 (list int [1,3,4])       == "[1,3,4]"
    -- encode 0 (list bool [True,False]) == "[true,false]"
    -- encode 0 (list string ["a","b"])  == """["a","b"]"""

-}
list : (a -> Value) -> List a -> Value
list =
    JE.list


{-| Turn an `Set` into a JSON array.
-}
set : (a -> Value) -> Set a -> Value
set =
    JE.set



-- OBJECTS


{-| Create a JSON object.

    import JE as Encode

    tom : Encode.Value
    tom =
        Encode.object
            [ ( "name", Encode.string "Tom" )
            , ( "age", Encode.int 42 )
            ]

    -- Encode.encode 0 tom == """{"name":"Tom","age":42}"""

-}
object : List ( String, Value ) -> Value
object =
    JE.object


{-| Turn a `Dict` into a JSON object.

    import Dict exposing (Dict)
    import JE as Encode

    people : Dict String Int
    people =
        Dict.fromList [ ( "Tom", 42 ), ( "Sue", 38 ) ]

    -- Encode.encode 0 (Encode.dict identity Encode.int people)
    --   == """{"Tom":42,"Sue":38}"""

-}
dict : (k -> String) -> (v -> Value) -> Dict k v -> Value
dict =
    JE.dict


{-| Encode a `LocalTime` value into a JSON float representing the number of seconds
since epoch.

    import Json.Encode exposing (..)
    import Time

    encode 0
        ( object
            [ ( "created_at", localTime (Time.millisToPosix 1574447205 ) ) ]
        )
        --> "{\"created_at\":1574447.205}"

-}
localTime : LocalTime -> Value
localTime =
    JEE.posix


{-| Encode a `Maybe` value with the given encoder.

    import Json.Encode exposing (..)

    encode 0 (maybe int Nothing)
        --> "null"

    encode 0 (maybe int (Just 1))
        --> "1"

-}
maybe : (a -> Value) -> Maybe a -> Value
maybe =
    JEE.maybe
