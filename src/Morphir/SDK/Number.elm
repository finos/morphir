module Morphir.SDK.Number exposing (..)

{-| Basic operations on numbers.
-}


{-| Add two numbers. The `number` type variable means this operation can be
specialized to `Int -> Int -> Int` or to `Float -> Float -> Float`. So you
can do things like this:

    3002 + 4004 == 7006 -- all ints

    3.14 + 3.14 == 6.28 -- all floats

You _cannot_ add an `Int` and a `Float` directly though. Use functions like
[toFloat](#toFloat) or [round](#round) to convert both values to the same type.
So if you needed to add a list length to a `Float` for some reason, you
could say one of these:

    3.14 + toFloat (List.length [ 1, 2, 3 ]) == 6.14

    round 3.14 + List.length [ 1, 2, 3 ] == 6

**Note:** Languages like Java and JavaScript automatically convert `Int` values
to `Float` values when you mix and match. This can make it difficult to be sure
exactly what type of number you are dealing with. When you try to _infer_ these
conversions (as Scala does) it can be even more confusing. Elm has opted for a
design that makes all conversions explicit.

-}
add : number -> number -> number
add =
    (+)


{-| Subtract numbers like `4 - 3 == 1`.

See [`add`](#+) for docs on the `number` type variable.

-}
subtract : number -> number -> number
subtract =
    (-)


{-| Multiply numbers like `2 * 3 == 6`.

See [`add`](#+) for docs on the `number` type variable.

-}
multiply : number -> number -> number
multiply =
    (*)


{-| Exponentiation

    3 ^ 2 == 9

    3 ^ 3 == 27

-}
pow : number -> number -> number
pow =
    (^)


{-| Negate a number.

    negate 42 == -42

    negate -42 == 42

    negate 0 == 0

-}
negate : number -> number
negate n =
    -n


{-| Get the [absolute value][abs] of a number.

    abs 16 == 16

    abs -4 == 4

    abs -8.5 == 8.5

    abs 3.14 == 3.14

[abs]: https://en.wikipedia.org/wiki/Absolute_value

-}
abs : number -> number
abs n =
    if lt n 0 then
        -n

    else
        n


{-| Clamps a number within a given range. With the expression
`clamp 100 200 x` the results are as follows:

    100     if x < 100
     x      if 100 <= x < 200
    200     if 200 <= x

-}
clamp : number -> number -> number -> number
clamp low high number =
    if lt number low then
        low

    else if gt number high then
        high

    else
        number
