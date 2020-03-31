module Main exposing (Age, Animal, Color(..), Li(..), Name, Option(..), Person, Player, Point(..), User(..), decoderAge, decoderAnimal, decoderColor, decoderMaybeString, decoderName, decoderPerson, decoderPlayer, decoderPoint, decoderUser, encodeAge, encodeAnimal, encodeColor, encodeMaybeString, encodeName, encodePerson, encodePlayer, encodePoint, encodeUser, intListDecoder, intListEncode)

import Json.Decode as D exposing (..)
import Json.Encode as E exposing (..)


{-|

    Type aliases

-}
type alias Name =
    String


type alias Age =
    Int


{-|

    Simple type alias json
    "\"John\""
    4

-}
encodeName : Name -> E.Value
encodeName name =
    E.string name


decoderName : Decoder Name
decoderName =
    D.string


encodeAge : Age -> E.Value
encodeAge age =
    E.int age


decoderAge : Decoder Age
decoderAge =
    D.int


{-|

    Records with primitive fields

-}
type alias Animal =
    { name : String }


type alias Person =
    { name : String, age : Int }


{-|

    Record with primitive fields json

    Animal:

    {
        "animal" :
            {
                "name" : "\"Cat\""
            }
    }

    Person:

    {
        "person" :
            {
                "name" : "\"John\"",
                "age" : 34
            }
    }

-}
encodeAnimal : Animal -> E.Value
encodeAnimal animal =
    object
        [ ( "animal"
          , object
                [ ( "name", E.string animal.name ) ]
          )
        ]


decoderAnimal : Decoder Animal
decoderAnimal =
    map Animal (at [ "animal", "name" ] D.string)


encodePerson : Person -> E.Value
encodePerson person =
    object
        [ ( "person"
          , object
                [ ( "name", E.string person.name )
                , ( "age", E.int person.age )
                ]
          )
        ]


decoderPerson : Decoder Person
decoderPerson =
    map2
        Person
        (at [ "person", "name" ] D.string)
        (at [ "pseron", "age" ] D.int)


{-|

    Simple custom types

-}
type Color
    = Red
    | Green
    | Blue


type Point
    = Point Int Int


{-|

    Simple custom types json

    {
        "$type" :
            {
                "red" : {}
            }
    }

    {
        "$type" :
            {
                "green" : {}
            }
    }

    {
        "point" :
            {
                "$pos1" : 3,
                "$pos2" : 4
            }
    }

-}
encodeColor : Color -> E.Value
encodeColor color =
    case color of
        Red ->
            object [ ( "red", object [] ) ]

        Green ->
            object [ ( "green", object [] ) ]

        Blue ->
            object [ ( "blue", object [] ) ]


decoderColor : Decoder Color
decoderColor =
    D.oneOf
        [ at [ "$types", "red" ] (succeed Red)
        , at [ "$types", "green" ] (succeed Green)
        , at [ "$types", "blue" ] (succeed Blue)
        ]


encodePoint : Point -> E.Value
encodePoint (Point pos0 pos1) =
    object
        [ ( "point"
          , object
                [ ( "$pos0", E.int pos0 )
                , ( "$pos1", E.int pos1 )
                ]
          )
        ]


decoderPoint : Decoder Point
decoderPoint =
    map2
        Point
        (at [ "point", "$pos1" ] D.int)
        (at [ "point", "$pos2" ] D.int)


{-|

    Complex custom types

-}
type User
    = Regular String
    | Visitor


{-|

    Complex custom type json

    Regular json:

    {
        "regular" :
            {
                "$pos1" : "\"John\""
            }
    }

    Visitor json:

    {
        "visitor" : {}
    }

-}
encodeUser : User -> E.Value
encodeUser user =
    case user of
        Regular pos1 ->
            object [ ( "regular", object [ ( "$pos1", E.string pos1 ) ] ) ]

        Visitor ->
            object [ ( "visit", object [] ) ]


decoderUser : Decoder User
decoderUser =
    oneOf
        [ field "visitor" (succeed Visitor)
        , map Regular (at [ "regular", "$pos1" ] D.string)
        ]


{-|

    Custom types with generics a.k.a. higher kinded type (* -> *)

-}
type Option a
    = None
    | Some a


type Li a
    = Empty
    | Cons a (Li a)


{-|

    Higher kinded types cannot be encoded to json hence they should be completely evaluated before
    they can be encoded to json.

    Maybe String
        Nothing :
            "null"
        Just "helloworld" :
            "\"helloworld\""

    List Int
        Empty :
            []
        Non-empty :
            [1, 2, 3]

-}
encodeMaybeString : Maybe String -> E.Value
encodeMaybeString arg =
    case arg of
        Just a ->
            E.string a

        Nothing ->
            E.null


decoderMaybeString : Decoder (Maybe String)
decoderMaybeString =
    nullable D.string


intListEncode : List Int -> E.Value
intListEncode li =
    E.list E.int li


intListDecoder : Decoder (List Int)
intListDecoder =
    D.list D.int


{-|

    Rcord type with primitive, alias, simple cutom type and complex cutom type

    player json:

    {
        "player" :
            {
                "name" : "\"John\"",
                "age" : 23
                "team" :
                    {
                        "red" : {}
                    },
                "position" :
                    {
                        "point" :
                            {
                                "$pos1" : 3,
                                "$pos2" : 4
                            }
                    }
            }
    }

-}
type alias Player =
    { name : String, age : Age, team : Color, position : Point }


encodePlayer : Player -> E.Value
encodePlayer player =
    E.object
        [ ( "player"
          , E.object
                [ ( "name", E.string player.name )
                , ( "age", encodeAge player.age )
                , ( "team", encodeColor player.team )
                , ( "position", encodePoint player.position )
                ]
          )
        ]


decoderPlayer : Decoder Player
decoderPlayer =
    map4
        Player
        (at [ "player", "name" ] decoderName)
        (at [ "player", "age" ] decoderAge)
        (at [ "player", "team" ] decoderColor)
        (at [ "player", "position" ] decoderPoint)
