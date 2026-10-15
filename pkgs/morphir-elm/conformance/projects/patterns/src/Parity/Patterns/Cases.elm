module Parity.Patterns.Cases exposing (Shape(..), area, ints, textual, tuples, lists, nested, named, flags, sign)

{-| Every pattern form that morphir-elm maps, and `if` with `else if`. -}


type Shape
    = Circle Float
    | Rect Float Float
    | Empty

area : Shape -> Float
area shape = case shape of
    Circle r -> r * r
    Rect w h -> w * h
    Empty -> 0

ints : Int -> Int
ints n = case n of
    0 -> 1
    0x10 -> 2
    _ -> n

textual : Char -> String -> Int
textual c s = case ( c, s ) of
    ( 'a', _ ) -> 1
    ( _, "a" ) -> 2
    ( other, _ ) -> Char.toCode other

tuples : ( Int, Bool ) -> Int
tuples t = case t of
    ( 0, True ) -> 0
    ( n, False ) -> n
    ( n, _ ) -> -n

lists : List Int -> Int
lists l = case l of
    [] -> 0
    [ a ] -> a
    [ a, b ] -> a + b
    x :: rest -> x + List.length rest

nested : Maybe Shape -> Float
nested m = case m of
    Maybe.Just (Circle r) -> r
    Just (Rect w _) -> w
    _ -> 0

named : Maybe Int -> Maybe Int
named m = case m of
    (Just _) as whole -> whole
    Nothing -> Nothing

flags : () -> Bool -> Int
flags u b = case ( u, b ) of
    ( (), True ) -> 1
    ( (), False ) -> 0

sign : Int -> Int
sign n = if n < 0 then -1 else if n == 0 then 0 else 1
