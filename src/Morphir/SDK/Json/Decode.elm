module Morphir.SDK.Json.Decode exposing
    ( Decoder, string, bool, int, float
    , nullable, list, dict, keyValuePairs, oneOrMore
    , field, at, index
    , maybe, oneOf
    , decodeString, decodeValue, Value, Error, errorToString
    , map, map2, map3, map4, map5, map6, map7, map8
    , lazy, value, null, succeed, fail, andThen
    , date, localTime, nothing
    )

{-| Turn JSON values into Elm values. Definitely check out this [intro to
JSON decoders][guide] to get a feel for how this library works!

[guide]: https://guide.elm-lang.org/effects/json.html


# Primitives

@docs Decoder, string, bool, int, float


# Data Structures

@docs nullable, list, dict, keyValuePairs, oneOrMore


# Object Primitives

@docs field, at, index


# Inconsistent Structure

@docs maybe, oneOf


# Run Decoders

@docs decodeString, decodeValue, Value, Error, errorToString


# Mapping

**Note:** If you run out of map functions, take a look at [elm-json-decode-pipeline][pipe]
which makes it easier to handle large objects, but produces lower quality type
errors.

[pipe]: /packages/NoRedInk/elm-json-decode-pipeline/latest

@docs map, map2, map3, map4, map5, map6, map7, map8


# Fancy Decoding

@docs lazy, value, null, succeed, fail, andThen


# Extra

@docs date, localTime, nothing

-}

import Dict exposing (Dict)
import Json.Decode as DE
import Json.Decode.Extra as DEE
import Json.Encode exposing (Value)
import Morphir.SDK.LocalDate exposing (Month, intToMonth)
import Morphir.SDK.LocalTime exposing (LocalTime)



-- PRIMITIVES


{-| A value that knows how to decode JSON values.

There is a whole section in `guide.elm-lang.org` about decoders, so [check it
out](https://guide.elm-lang.org/interop/json.html) for a more comprehensive
introduction!

-}
type alias Decoder a =
    DE.Decoder a


{-| A structured error describing exactly how the decoder failed. You can use
this to create more elaborate visualizations of a decoder problem. For example,
you could show the entire JSON object and show the part causing the failure in
red.
-}
type alias Error =
    DE.Error


{-| Decode a JSON string into an Elm `String`.

    decodeString string "true"              == Err ...
    decodeString string "42"                == Err ...
    decodeString string "3.14"              == Err ...
    decodeString string "\"hello\""         == Ok "hello"
    decodeString string "{ \"hello\": 42 }" == Err ...

-}
string : Decoder String
string =
    DE.string


{-| Decode a JSON boolean into an Elm `Bool`.

    decodeString bool "true"              == Ok True
    decodeString bool "42"                == Err ...
    decodeString bool "3.14"              == Err ...
    decodeString bool "\"hello\""         == Err ...
    decodeString bool "{ \"hello\": 42 }" == Err ...

-}
bool : Decoder Bool
bool =
    DE.bool


{-| Decode a JSON number into an Elm `Int`.

    decodeString int "true"              == Err ...
    decodeString int "42"                == Ok 42
    decodeString int "3.14"              == Err ...
    decodeString int "\"hello\""         == Err ...
    decodeString int "{ \"hello\": 42 }" == Err ...

-}
int : Decoder Int
int =
    DE.int


{-| Decode a JSON number into an Elm `Float`.

    decodeString float "true"              == Err ..
    decodeString float "42"                == Ok 42
    decodeString float "3.14"              == Ok 3.14
    decodeString float "\"hello\""         == Err ...
    decodeString float "{ \"hello\": 42 }" == Err ...

-}
float : Decoder Float
float =
    DE.float



-- DATA STRUCTURES


{-| Decode a nullable JSON value into an Elm value.

    decodeString (nullable int) "13"    == Ok (Just 13)
    decodeString (nullable int) "42"    == Ok (Just 42)
    decodeString (nullable int) "null"  == Ok Nothing
    decodeString (nullable int) "true"  == Err ..

-}
nullable : Decoder a -> Decoder (Maybe a)
nullable =
    DE.nullable


{-| Decode a JSON array into an Elm `List`.

    decodeString (list int) "[1,2,3]" == Ok [ 1, 2, 3 ]

    decodeString (list bool) "[true,false]" == Ok [ True, False ]

-}
list : Decoder a -> Decoder (List a)
list =
    DE.list


{-| Decode a JSON object into an Elm `Dict`.

    decodeString (dict int) "{ \"alice\": 42, \"bob\": 99 }"
        == Ok (Dict.fromList [ ( "alice", 42 ), ( "bob", 99 ) ])

If you need the keys (like `"alice"` and `"bob"`) available in the `Dict`
values as well, I recommend using a (private) intermediate data structure like
`Info` in this example:

    module User exposing (User, decoder)

    import Dict
    import Json.Decode exposing (..)

    type alias User =
        { name : String
        , height : Float
        , age : Int
        }

    decoder : Decoder (Dict.Dict String User)
    decoder =
        map (Dict.map infoToUser) (dict infoDecoder)

    type alias Info =
        { height : Float
        , age : Int
        }

    infoDecoder : Decoder Info
    infoDecoder =
        map2 Info
            (field "height" float)
            (field "age" int)

    infoToUser : String -> Info -> User
    infoToUser name { height, age } =
        User name height age

So now JSON like `{ "alice": { height: 1.6, age: 33 }}` are turned into
dictionary values like `Dict.singleton "alice" (User "alice" 1.6 33)` if
you need that.

-}
dict : Decoder a -> Decoder (Dict String a)
dict =
    DE.dict


{-| Decode a JSON object into an Elm `List` of pairs.

    decodeString (keyValuePairs int) "{ \"alice\": 42, \"bob\": 99 }"
        == Ok [ ( "alice", 42 ), ( "bob", 99 ) ]

-}
keyValuePairs : Decoder a -> Decoder (List ( String, a ))
keyValuePairs =
    DE.keyValuePairs


{-| Decode a JSON array that has one or more elements. This comes up if you
want to enable drag-and-drop of files into your application. You would pair
this function with [`elm/file`]() to write a `dropDecoder` like this:

    import File exposing (File)
    import Json.Decoder as D

    type Msg
        = GotFiles File (List Files)

    inputDecoder : D.Decoder Msg
    inputDecoder =
        D.at [ "dataTransfer", "files" ] (D.oneOrMore GotFiles File.decoder)

This captures the fact that you can never drag-and-drop zero files.

-}
oneOrMore : (a -> List a -> value) -> Decoder a -> Decoder value
oneOrMore =
    DE.oneOrMore



-- OBJECT PRIMITIVES


{-| Decode a JSON object, requiring a particular field.

    decodeString (field "x" int) "{ \"x\": 3 }" == Ok 3

    decodeString (field "x" int) "{ \"x\": 3, \"y\": 4 }" == Ok 3

    decodeString (field "x" int) "{ \"x\": true }"
        == Err
        ... decodeString (field "x" int) "{ \"y\": 4 }"
        == Err
        ... decodeString (field "name" string) "{ \"name\": \"tom\" }"
        == Ok "tom"

The object _can_ have other fields. Lots of them! The only thing this decoder
cares about is if `x` is present and that the value there is an `Int`.

Check out [`map2`](#map2) to see how to decode multiple fields!

-}
field : String -> Decoder a -> Decoder a
field =
    DE.field


{-| Decode a nested JSON object, requiring certain fields.

    json = """{ "person": { "name": "tom", "age": 42 } }"""

    decodeString (at ["person", "name"] string) json  == Ok "tom"
    decodeString (at ["person", "age" ] int   ) json  == Ok "42

This is really just a shorthand for saying things like:

    field "person" (field "name" string) == at [ "person", "name" ] string

-}
at : List String -> Decoder a -> Decoder a
at =
    DE.at


{-| Decode a JSON array, requiring a particular index.

    json = """[ "alice", "bob", "chuck" ]"""

    decodeString (index 0 string) json  == Ok "alice"
    decodeString (index 1 string) json  == Ok "bob"
    decodeString (index 2 string) json  == Ok "chuck"
    decodeString (index 3 string) json  == Err ...

-}
index : Int -> Decoder a -> Decoder a
index =
    DE.index



-- WEIRD STRUCTURE


{-| Helpful for dealing with optional fields. Here are a few slightly different
examples:

    json = """{ "name": "tom", "age": 42 }"""

    decodeString (maybe (field "age"    int  )) json == Ok (Just 42)
    decodeString (maybe (field "name"   int  )) json == Ok Nothing
    decodeString (maybe (field "height" float)) json == Ok Nothing

    decodeString (field "age"    (maybe int  )) json == Ok (Just 42)
    decodeString (field "name"   (maybe int  )) json == Ok Nothing
    decodeString (field "height" (maybe float)) json == Err ...

Notice the last example! It is saying we _must_ have a field named `height` and
the content _may_ be a float. There is no `height` field, so the decoder fails.

Point is, `maybe` will make exactly what it contains conditional. For optional
fields, this means you probably want it _outside_ a use of `field` or `at`.

-}
maybe : Decoder a -> Decoder (Maybe a)
maybe =
    DE.maybe


{-| Try a bunch of different decoders. This can be useful if the JSON may come
in a couple different formats. For example, say you want to read an array of
numbers, but some of them are `null`.

    import String

    badInt : Decoder Int
    badInt =
        oneOf [ int, null 0 ]

    -- decodeString (list badInt) "[1,2,null,4]" == Ok [1,2,0,4]

Why would someone generate JSON like this? Questions like this are not good
for your health. The point is that you can use `oneOf` to handle situations
like this!

You could also use `oneOf` to help version your data. Try the latest format,
then a few older ones that you still support. You could use `andThen` to be
even more particular if you wanted.

-}
oneOf : List (Decoder a) -> Decoder a
oneOf =
    DE.oneOf



-- MAPPING


{-| Transform a decoder. Maybe you just want to know the length of a string:

    import String

    stringLength : Decoder Int
    stringLength =
        map String.length string

It is often helpful to use `map` with `oneOf`, like when defining `nullable`:

    nullable : Decoder a -> Decoder (Maybe a)
    nullable decoder =
        oneOf
            [ null Nothing
            , map Just decoder
            ]

-}
map : (a -> value) -> Decoder a -> Decoder value
map =
    DE.map


{-| Try two decoders and then combine the result. We can use this to decode
objects with many fields:


    type alias Point =
        { x : Float, y : Float }

    point : Decoder Point
    point =
        map2 Point
            (field "x" float)
            (field "y" float)

    -- decodeString point """{ "x": 3, "y": 4 }""" == Ok { x = 3, y = 4 }

It tries each individual decoder and puts the result together with the `Point`
constructor.

-}
map2 : (a -> b -> value) -> Decoder a -> Decoder b -> Decoder value
map2 =
    DE.map2


{-| Try three decoders and then combine the result. We can use this to decode
objects with many fields:


    type alias Person =
        { name : String, age : Int, height : Float }

    person : Decoder Person
    person =
        map3 Person
            (at [ "name" ] string)
            (at [ "info", "age" ] int)
            (at [ "info", "height" ] float)

    -- json = """{ "name": "tom", "info": { "age": 42, "height": 1.8 } }"""
    -- decodeString person json == Ok { name = "tom", age = 42, height = 1.8 }

Like `map2` it tries each decoder in order and then give the results to the
`Person` constructor. That can be any function though!

-}
map3 : (a -> b -> c -> value) -> Decoder a -> Decoder b -> Decoder c -> Decoder value
map3 =
    DE.map3


{-| -}
map4 : (a -> b -> c -> d -> value) -> Decoder a -> Decoder b -> Decoder c -> Decoder d -> Decoder value
map4 =
    DE.map4


{-| -}
map5 : (a -> b -> c -> d -> e -> value) -> Decoder a -> Decoder b -> Decoder c -> Decoder d -> Decoder e -> Decoder value
map5 =
    DE.map5


{-| -}
map6 : (a -> b -> c -> d -> e -> f -> value) -> Decoder a -> Decoder b -> Decoder c -> Decoder d -> Decoder e -> Decoder f -> Decoder value
map6 =
    DE.map6


{-| -}
map7 : (a -> b -> c -> d -> e -> f -> g -> value) -> Decoder a -> Decoder b -> Decoder c -> Decoder d -> Decoder e -> Decoder f -> Decoder g -> Decoder value
map7 =
    DE.map7


{-| -}
map8 : (a -> b -> c -> d -> e -> f -> g -> h -> value) -> Decoder a -> Decoder b -> Decoder c -> Decoder d -> Decoder e -> Decoder f -> Decoder g -> Decoder h -> Decoder value
map8 =
    DE.map8



-- RUN DECODERS


{-| Parse the given string into a JSON value and then run the `Decoder` on it.
This will fail if the string is not well-formed JSON or if the `Decoder`
fails for some reason.

    decodeString int "4"     == Ok 4
    decodeString int "1 + 2" == Err ...

-}
decodeString : Decoder a -> String -> Result Error a
decodeString =
    DE.decodeString


{-| Run a `Decoder` on some JSON `Value`. You can send these JSON values
through ports, so that is probably the main time you would use this function.
-}
decodeValue : Decoder a -> Value -> Result Error a
decodeValue =
    DE.decodeValue


{-| Represents a JavaScript value.
-}
type alias Value =
    Json.Encode.Value


{-| Convert a decoding error into a `String` that is nice for debugging.

It produces multiple lines of output, so you may want to peek at it with
something like this:

    import Html
    import Json.Decode as Decode

    errorToHtml : Decode.Error -> Html.Html msg
    errorToHtml error =
        Html.pre [] [ Html.text (Decode.errorToString error) ]

**Note:** It would be cool to do nicer coloring and fancier HTML, but I wanted
to avoid having an `elm/html` dependency for now. It is totally possible to
crawl the `Error` structure and create this separately though!

-}
errorToString : Error -> String
errorToString =
    DE.errorToString



-- FANCY PRIMITIVES


{-| Ignore the JSON and produce a certain Elm value.

    decodeString (succeed 42) "true"    == Ok 42
    decodeString (succeed 42) "[1,2,3]" == Ok 42
    decodeString (succeed 42) "hello"   == Err ... -- this is not a valid JSON string

This is handy when used with `oneOf` or `andThen`.

-}
succeed : a -> Decoder a
succeed =
    DE.succeed


{-| Ignore the JSON and make the decoder fail. This is handy when used with
`oneOf` or `andThen` where you want to give a custom error message in some
case.

See the [`andThen`](#andThen) docs for an example.

-}
fail : String -> Decoder a
fail =
    DE.fail


{-| Create decoders that depend on previous results. If you are creating
versioned data, you might do something like this:


    info : Decoder Info
    info =
        field "version" int
            |> andThen infoHelp

    infoHelp : Int -> Decoder Info
    infoHelp version =
        case version of
            4 ->
                infoDecoder4

            3 ->
                infoDecoder3

            _ ->
                fail <|
                    "Trying to decode info, but version "
                        ++ toString version
                        ++ " is not supported."

    -- infoDecoder4 : Decoder Info
    -- infoDecoder3 : Decoder Info

-}
andThen : (a -> Decoder b) -> Decoder a -> Decoder b
andThen =
    DE.andThen


{-| Sometimes you have JSON with recursive structure, like nested comments.
You can use `lazy` to make sure your decoder unrolls lazily.

    type alias Comment =
        { message : String
        , responses : Responses
        }

    type Responses
        = Responses (List Comment)

    comment : Decoder Comment
    comment =
        map2 Comment
            (field "message" string)
            (field "responses" (map Responses (list (lazy (\_ -> comment)))))

If we had said `list comment` instead, we would start expanding the value
infinitely. What is a `comment`? It is a decoder for objects where the
`responses` field contains comments. What is a `comment` though? Etc.

By using `list (lazy (\_ -> comment))` we make sure the decoder only expands
to be as deep as the JSON we are given. You can read more about recursive data
structures [here].

[here]: https://github.com/elm/compiler/blob/master/hints/recursive-alias.md

-}
lazy : (() -> Decoder a) -> Decoder a
lazy =
    DE.lazy


{-| Do not do anything with a JSON value, just bring it into Elm as a `Value`.
This can be useful if you have particularly complex data that you would like to
deal with later. Or if you are going to send it out a port and do not care
about its structure.
-}
value : Decoder Value
value =
    DE.value


{-| Decode a `null` value into some Elm value.

    decodeString (null False) "null" == Ok False
    decodeString (null 42) "null"    == Ok 42
    decodeString (null 42) "42"      == Err ..
    decodeString (null 42) "false"   == Err ..

So if you ever see a `null`, this will return whatever value you specified.

-}
null : a -> Decoder a
null =
    DE.null


{-| Decode a JSON value and do nothing with it.

    import Json.Decode exposing (..)

    decodeString nothing "{}" --> Ok ()

-}
nothing : Decoder ()
nothing =
    DEE.nothing


{-| Decode a JSON float value representing the number of seconds since epoch
into a `LocalTime`.

    import Json.Decode exposing (..)
    import Time

    decodeString (field "created_at" localTime)
        "{ \"created_at\": 1574447205.394}"
        --> Ok (Time.millisToPosix 1574447205000)

-}
localTime : Decoder LocalTime
localTime =
    DEE.posix


{-| Decode an ISO8601 JSON string into a `Posix`.

    import Json.Decode exposing (..)
    import Time

    decodeString (field "created_at" date) "{ \"created_at\": \"2019-11-22\"}"
        --> Ok (2019, Time.Nov, 22)

-}
date : Decoder ( Int, Month, Int )
date =
    string
        |> andThen
            (\val ->
                case String.split "-" val of
                    [ y_, m_, d_ ] ->
                        Maybe.map3
                            (\a b c -> succeed ( a, b, c ))
                            (String.right 4 y_ |> String.toInt)
                            (String.right 2 m_
                                |> String.toInt
                                |> Maybe.andThen intToMonth
                            )
                            (String.right 2 d_ |> String.toInt)
                            |> Maybe.withDefault (fail ("Unknown dat value: " ++ val))

                    _ ->
                        fail ("Unknown date value: " ++ val)
            )
