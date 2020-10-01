module Morphir.IR.Type.UnionFind exposing (..)


type Point a
    = Pt (PointInfo a)


type PointInfo a
    = Info Int a
    | Link (Point a)


fresh : a -> Point a
fresh value =
    let
        weight =
            1

        desc =
            value

        link =
            Info weight desc
    in
    Pt link
