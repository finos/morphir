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


module Morphir.SDK.Int exposing
    ( Int8, fromInt8, toInt8
    , Int16, fromInt16, toInt16
    , Int32, fromInt32, toInt32
    , Int64, fromInt64, toInt64
    )

{-| This module adds some support for fixed precision integers. We intentionally limit the operations that you can do
on fixed precision integers because in general it's difficult to decide whether a calculation will result in an overflow
in the general case. At the same time having the ability to encode fixed precision integers in your domain model can be
very useful. This module allows you to do that while making sure that you can only use arbitrary precision integers
in your calculation.

Example use:

    calc : Int8 -> Int16 -> Int8
    calc a b =
        let
            arbA =
                Int.fromInt8 a

            abrB =
                Int.fromInt16 b
        in
        arbA
            * arbB
            |> Int.toInt8
            |> Maybe.withDefault 0

The above example shows how the user is required to either provide a default value or change the return type of the
function to handle cases where the calculation might return a value that doesn't fit in the 8 bit precision.

@docs Int8, fromInt8, toInt8
@docs Int16, fromInt16, toInt16
@docs Int32, fromInt32, toInt32
@docs Int64, fromInt64, toInt64

-}


{-| Represents an 8 bit integer value.
-}
type Int8
    = Int8 Int


{-| Turn an 8 bit integer value into an arbitrary precision integer to use in calculations.
-}
fromInt8 : Int8 -> Int
fromInt8 (Int8 int) =
    int


{-| Turn an arbitrary precision integer into an 8 bit integer if it fits within the precision.
-}
toInt8 : Int -> Maybe Int8
toInt8 int =
    if int < -128 || int > 127 then
        Nothing

    else
        Just (Int8 int)


{-| Represents a 16 bit integer value.
-}
type Int16
    = Int16 Int


{-| Turn an 16 bit integer value into an arbitrary precision integer to use in calculations.
-}
fromInt16 : Int16 -> Int
fromInt16 (Int16 int) =
    int


{-| Turn an arbitrary precision integer into an 16 bit integer if it fits within the precision.
-}
toInt16 : Int -> Maybe Int16
toInt16 int =
    if int < -32768 || int > 32767 then
        Nothing

    else
        Just (Int16 int)


{-| Represents a 32 bit integer value.
-}
type Int32
    = Int32 Int


{-| Turn an 32 bit integer value into an arbitrary precision integer to use in calculations.
-}
fromInt32 : Int32 -> Int
fromInt32 (Int32 int) =
    int


{-| Turn an arbitrary precision integer into an 32 bit integer if it fits within the precision.
-}
toInt32 : Int -> Maybe Int32
toInt32 int =
    if int < -2147483648 || int > 2147483647 then
        Nothing

    else
        Just (Int32 int)


{-| Represents a 64 bit integer value.
-}
type Int64
    = Int64 Int


{-| Turn an 64 bit integer value into an arbitrary precision integer to use in calculations.
-}
fromInt64 : Int64 -> Int
fromInt64 (Int64 int) =
    int


{-| Turn an arbitrary precision integer into an 64 bit integer if it fits within the precision.
-}
toInt64 : Int -> Maybe Int64
toInt64 int =
    if int < -9223372036854775808 || int > 9223372036854775807 then
        Nothing

    else
        Just (Int64 int)
