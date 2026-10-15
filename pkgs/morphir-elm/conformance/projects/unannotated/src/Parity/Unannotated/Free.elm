module Parity.Unannotated.Free exposing (un, unannot, unannot2, unFloat, unRec, useUn, total)

{-| Values without a type annotation, and one annotated value that uses them. -}


un =
    1

unannot a b =
    a

unannot2 a =
    a + 1

unFloat =
    1.5 + 1

unRec r =
    r.x

useUn =
    unannot 1 2

total : Int
total =
    un + useUn + unannot2 3 + unRec { x = 4 }
