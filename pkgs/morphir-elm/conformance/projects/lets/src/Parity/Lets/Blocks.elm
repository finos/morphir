module Parity.Lets.Blocks exposing (inOrder, reordered, chain, function, annotated, destructure, selfRecursive, mutual, scaled)

{-| Let blocks: dependency order, let functions, destructuring and recursion. -}


inOrder : Int
inOrder =
    let a = 1
        b = 2
    in a

reordered : Int
reordered =
    let a = b
        b = 1
        c = 2
    in c

chain : Int
chain =
    let x = 1
        y = z
        z = x
    in y

function : Int
function =
    let f x = x
    in f 1

annotated : Int
annotated =
    let g : Int -> Int
        g x = x
    in g 1

destructure : ( Int, Int ) -> Int
destructure t =
    let ( a, b ) = t
    in a

selfRecursive : Int
selfRecursive =
    let loop n = loop n
    in loop 1

mutual : Int
mutual =
    let p = q 1
        q k = r k
        r k = q k
        s = p
    in s

scaled : Float -> Float
scaled price =
    let rate = 2
    in price * rate
