module Parity.Custom.Shapes exposing (Shape(..), Tree(..), Opaque, Keyed(..), area, isLeaf, unwrap)

{-| Custom types. -}


{-| A shape. -}
type Shape
    = Circle Float
    | Rect Float Float
    | Dot


type Tree a
    = Leaf
    | Node (Tree a) a (Tree a)


type Opaque
    = Opaque Int


type Keyed comparable v
    = Keyed comparable v
    | Unkeyed (List v)


type Hidden
    = Hidden String
    | Shown


area : Shape -> Float
area shape =
    case shape of
        Circle r ->
            r * r

        Rect w h ->
            w * h

        Dot ->
            0


isLeaf : Tree a -> Bool
isLeaf tree =
    case tree of
        Leaf ->
            True

        Node _ _ _ ->
            False


unwrap : Opaque -> Int
unwrap opaque =
    case opaque of
        Opaque n ->
            n
