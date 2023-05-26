module Child.One.Module1 exposing (..)

import Parent.One.Module1


type alias Type1 =
    { parent1 : Parent.One.Module1.Type1
    , foo : String
    }


fun1 : Parent.One.Module1.Type1 -> Int
fun1 input =
    if input.bar then
        input.foo

    else
        0
