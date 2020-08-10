{-
Copyright 2020 Morgan Stanley

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}


module Morphir.SDK.Float exposing (..)

{-| A `Float` is a [floating-point number][fp]. Valid syntax for floats includes:

    0
    42
    3.14
    0.1234
    6.022e23   -- == (6.022 * 10^23)
    6.022e+23  -- == (6.022 * 10^23)
    1.602e−19  -- == (1.602 * 10^-19)
    1e3        -- == (1 * 10^3) == 1000

**Historical Note:** The particular details of floats (e.g. `NaN`) are
specified by [IEEE 754][ieee] which is literally hard-coded into almost all
CPUs in the world. That means if you think `NaN` is weird, you must
successfully overtake Intel and AMD with a chip that is not backwards
compatible with any widely-used assembly language.

[fp]: https://en.wikipedia.org/wiki/Floating-point_arithmetic
[ieee]: https://en.wikipedia.org/wiki/IEEE_754

-}

import Morphir.SDK.Int exposing (Int)


type alias Float =
    Basics.Float


{-| Represents a 32 bit floating-point value.
-}
type alias Float32 =
    Basics.Float


{-| Represents a 64 bit floating-point value.
-}
type alias Float64 =
    Basics.Float


{-| Floating-point division:

    10 / 4 == 2.5

    11 / 4 == 2.75

    12 / 4 == 3

    13 / 4 == 3.25

    14
        / 4
        == 3.5
        - 1
        / 4
        == -0.25
        - 5
        / 4
        == -1.25

-}
divide : Float -> Float -> Float
divide =
    (/)



-- INT TO FLOAT / FLOAT TO INT


{-| Convert an integer into a float. Useful when mixing `Int` and `Float`
values like this:

    halfOf : Int -> Float
    halfOf number =
        fromInt number / 2

-}
fromInt : Int -> Float
fromInt =
    Basics.toFloat


{-| Round a number to the nearest integer.

    round 1.0 == 1

    round 1.2 == 1

    round 1.5 == 2

    round 1.8 == 2

    round -1.2 == -1

    round -1.5 == -1

    round -1.8 == -2

-}
round : Float -> Int
round =
    Basics.round


{-| Floor function, rounding down.

    floor 1.0 == 1

    floor 1.2 == 1

    floor 1.5 == 1

    floor 1.8 == 1

    floor -1.2 == -2

    floor -1.5 == -2

    floor -1.8 == -2

-}
floor : Float -> Int
floor =
    Basics.floor


{-| Ceiling function, rounding up.

    ceiling 1.0 == 1

    ceiling 1.2 == 2

    ceiling 1.5 == 2

    ceiling 1.8 == 2

    ceiling -1.2 == -1

    ceiling -1.5 == -1

    ceiling -1.8 == -1

-}
ceiling : Float -> Int
ceiling =
    Basics.ceiling


{-| Truncate a number, rounding towards zero.

    truncate 1.0 == 1

    truncate 1.2 == 1

    truncate 1.5 == 1

    truncate 1.8 == 1

    truncate -1.2 == -1

    truncate -1.5 == -1

    truncate -1.8 == -1

-}
truncate : Float -> Int
truncate =
    Basics.truncate


{-| Take the square root of a number.

    sqrt 4 == 2

    sqrt 9 == 3

    sqrt 16 == 4

    sqrt 25 == 5

-}
sqrt : Float -> Float
sqrt =
    Elm.Kernel.Basics.sqrt


{-| Calculate the logarithm of a number with a given base.

    logBase 10 100 == 2

    logBase 2 256 == 8

-}
logBase : Float -> Float -> Float
logBase base number =
    divide
        (Elm.Kernel.Basics.log number)
        (Elm.Kernel.Basics.log base)


{-| An approximation of e.
-}
e : Float
e =
    Elm.Kernel.Basics.e



-- TRIGONOMETRY


{-| An approximation of pi.
-}
pi : Float
pi =
    Elm.Kernel.Basics.pi


{-| Figure out the cosine given an angle in radians.

    cos (degrees 60) == 0.5000000000000001

    cos (turns (1 / 6)) == 0.5000000000000001

    cos (radians (pi / 3)) == 0.5000000000000001

    cos (pi / 3) == 0.5000000000000001

-}
cos : Float -> Float
cos =
    Elm.Kernel.Basics.cos


{-| Figure out the sine given an angle in radians.

    sin (degrees 30) == 0.49999999999999994

    sin (turns (1 / 12)) == 0.49999999999999994

    sin (radians (pi / 6)) == 0.49999999999999994

    sin (pi / 6) == 0.49999999999999994

-}
sin : Float -> Float
sin =
    Elm.Kernel.Basics.sin


{-| Figure out the tangent given an angle in radians.

    tan (degrees 45) == 0.9999999999999999

    tan (turns (1 / 8)) == 0.9999999999999999

    tan (radians (pi / 4)) == 0.9999999999999999

    tan (pi / 4) == 0.9999999999999999

-}
tan : Float -> Float
tan =
    Elm.Kernel.Basics.tan


{-| Figure out the arccosine for `adjacent / hypotenuse` in radians:

    acos (1 / 2) == 1.0471975511965979 -- 60° or pi/3 radians

-}
acos : Float -> Float
acos =
    Elm.Kernel.Basics.acos


{-| Figure out the arcsine for `opposite / hypotenuse` in radians:

    asin (1 / 2) == 0.5235987755982989 -- 30° or pi/6 radians

-}
asin : Float -> Float
asin =
    Elm.Kernel.Basics.asin


{-| This helps you find the angle (in radians) to an `(x,y)` coordinate, but
in a way that is rarely useful in programming. **You probably want
[`atan2`](#atan2) instead!**

This version takes `y/x` as its argument, so there is no way to know whether
the negative signs comes from the `y` or `x` value. So as we go counter-clockwise
around the origin from point `(1,1)` to `(1,-1)` to `(-1,-1)` to `(-1,1)` we do
not get angles that go in the full circle:

    atan (1 / 1) == 0.7853981633974483 --  45° or   pi/4 radians

    atan (1 / -1) == -0.7853981633974483 -- 315° or 7*pi/4 radians

    atan (-1 / -1) == 0.7853981633974483 --  45° or   pi/4 radians

    atan (-1 / 1) == -0.7853981633974483 -- 315° or 7*pi/4 radians

Notice that everything is between `pi/2` and `-pi/2`. That is pretty useless
for figuring out angles in any sort of visualization, so again, check out
[`atan2`](#atan2) instead!

-}
atan : Float -> Float
atan =
    Elm.Kernel.Basics.atan


{-| This helps you find the angle (in radians) to an `(x,y)` coordinate.
So rather than saying `atan (y/x)` you say `atan2 y x` and you can get a full
range of angles:

    atan2 1 1 == 0.7853981633974483 --  45° or   pi/4 radians

    atan2 1 -1 == 2.356194490192345 -- 135° or 3*pi/4 radians

    atan2 -1 -1 == -2.356194490192345 -- 225° or 5*pi/4 radians

    atan2 -1 1 == -0.7853981633974483 -- 315° or 7*pi/4 radians

-}
atan2 : Float -> Float -> Float
atan2 =
    Elm.Kernel.Basics.atan2



-- CRAZY FLOATS


{-| Determine whether a float is an undefined or unrepresentable number.
NaN stands for _not a number_ and it is [a standardized part of floating point
numbers](https://en.wikipedia.org/wiki/NaN).

    isNaN (0 / 0) == True

    isNaN (sqrt -1) == True

    isNaN (1 / 0) == False -- infinity is a number

    isNaN 1 == False

-}
isNaN : Float -> Bool
isNaN =
    Elm.Kernel.Basics.isNaN


{-| Determine whether a float is positive or negative infinity.

    isInfinite (0 / 0) == False

    isInfinite (sqrt -1) == False

    isInfinite (1 / 0) == True

    isInfinite 1 == False

Notice that NaN is not infinite! For float `n` to be finite implies that
`not (isInfinite n || isNaN n)` evaluates to `True`.

-}
isInfinite : Float -> Bool
isInfinite =
    Elm.Kernel.Basics.isInfinite
