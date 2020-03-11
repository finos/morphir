module Morphir.Elm.Backend.Codec.Tests.A exposing (..)


type alias Name =
    String


type alias Age =
    Int


type alias Animal =
    { name : String }


type alias Person =
    { name : String, age : Int }


type Point
    = Point Int Int


type Color
    = Red
    | Green
    | Blue


type alias Player =
    { name : String, age : Age, team : Color, position : Point }


type alias User =
    { name : String, id : Maybe Int }
