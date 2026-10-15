module Parity.Lambdas.Fns exposing (Handler, twoArgs, tupleArg, wild, mixed, partial, paren, prefix, handler, mapped)

{-| Lambdas and how morphir-elm lifts the arguments of top-level values. -}


type alias Handler =
    Int -> Int

twoArgs : Int -> Int -> Int
twoArgs =
    \x y -> x + y

tupleArg : ( Int, Int ) -> Int
tupleArg =
    \( a, b ) -> a + b

wild : Int -> Int -> Int
wild _ y =
    y

mixed : Int -> ( Int, Int ) -> Int -> Int
mixed z ( a, b ) w =
    z + a + b + w

partial : Int -> Int -> Int
partial a =
    \b -> a + b

paren : Int -> Int -> Int
paren a =
    (\x -> a)

prefix : Int -> Int -> Int
prefix =
    (+)

handler : Handler
handler =
    \n -> n * 2

mapped : List Int -> List Int
mapped l =
    List.map (\v -> v + 1) l
