module Parity.Operators.Ops exposing (logic, ordering, ints, floats, text, lists, pipes, compose, prefix, partialPrefix, negations, precedence, wholeInFloat, floatList, literals)

{-| Every operator that morphir-elm maps, and the literal forms. -}


logic : Bool -> Bool -> Bool
logic a b = a || b && (a == b) || (a /= b)

ordering : Int -> Int -> List Bool
ordering a b = [ a < b, a > b, a <= b, a >= b ]

ints : Int -> Int -> Int
ints a b = a + b - a * b // 2 ^ b

floats : Float -> Float -> Float
floats x y = x / y + x ^ 2.5

text : String -> String -> String
text a b = a ++ b ++ "!"

lists : Int -> List Int -> List Int
lists x xs = x :: xs ++ [ x ]

pipes : Int -> Int
pipes a = (a |> negate |> abs) + (negate <| abs <| a)

compose : (Int -> Int) -> (Int -> Int) -> Int -> Int
compose f g = f >> g >> (f << g)

prefix : Int -> Int -> Int
prefix = (+)

partialPrefix : Int -> Int
partialPrefix = (+) 1

negations : Int -> (Int -> Int) -> List Int
negations x f = [ -x, -1, -(f x), -x ^ 2 ]

precedence : Int -> Int -> Int -> List Int
precedence a b c = [ a + b * c, a - b - 1 ]

wholeInFloat : Float -> Float
wholeInFloat x = x + 1

floatList : List Float
floatList = [ 1, 2.5, -2.5 ]

literals : ( Int, List Char, List String )
literals =
    ( 0xFF, [ 'a', '\n', '\'', '\u{1F600}' ], [ "tab\t", "quote\"", "\u{0041}", """multi
line""" ] )
