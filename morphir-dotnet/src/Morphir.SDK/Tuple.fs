module Morphir.SDK.Tuple

let inline pair a b = (a, b)

let inline first (a, _) = a

let inline second (_, b) = b

let mapFirst (func: 'a -> 'x) (x: 'a, y: 'b) = func x, y

let mapSecond (func: 'b -> 'y) (x: 'a, y: 'b) = x, func y

let mapBoth (funcA: 'a -> 'x) (funcB: 'b -> 'y) (a, b) = funcA a, funcB b
