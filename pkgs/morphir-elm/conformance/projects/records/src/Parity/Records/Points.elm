module Parity.Records.Points exposing (Point, origin, make, partial, getX, xs, moveArg, moveTop, readX)

{-| Record literals, alias constructors, field access and record updates. -}


type alias Point =
    { x : Int, y : Int }

origin : Point
origin =
    { y = 0, x = 0 }

make : Point
make =
    Point 1 2

partial : Int -> Point
partial =
    Point 1

getX : Point -> Int
getX p =
    p.x

xs : List Point -> List Int
xs points =
    List.map .x points

moveArg : Point -> Point
moveArg p =
    { p | x = 1 }

moveTop : Point
moveTop =
    { origin | x = 1, y = 2 }

readX : { a | x : Int } -> Int
readX r =
    r.x
