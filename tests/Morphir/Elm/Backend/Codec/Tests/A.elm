-- TODO: Fix module path name


module A exposing (..)


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


type User
    = Regular String Int
    | Visitor String


type alias TempEmployee =
    { name : String, id : Maybe Int }


type Employee
    = Perm String Int
    | Temp TempEmployee
