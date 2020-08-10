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


module Morphir.SDK.Comparable exposing (lessThan, greaterThan, lessThanOrEqual, greaterThanOrEqual, max, min, compare, Order)

{-| Comparing ordered values.

These functions only work on `comparable` types. This includes numbers,
characters, strings, lists of comparable things, and tuples of comparable
things.

@docs lessThan, greaterThan, lessThanOrEqual, greaterThanOrEqual, max, min, compare, Order

-}

import Morphir.SDK.Bool exposing (Bool)


{-| Check if the first value is less than the second.
-}
lessThan : comparable -> comparable -> Bool
lessThan =
    (<)


{-| Check if the first value is greater than the second.
-}
greaterThan : comparable -> comparable -> Bool
greaterThan =
    (>)


{-| Check if the first value is less than or equal to the second.
-}
lessThanOrEqual : comparable -> comparable -> Bool
lessThanOrEqual =
    (<=)


{-| Check if the first value is greater than or equal to the second.
-}
greaterThanOrEqual : comparable -> comparable -> Bool
greaterThanOrEqual =
    (>=)


{-| Find the smaller of two comparables.

    min 42 12345678 == 42

    min "abc" "xyz" == "abc"

-}
min : comparable -> comparable -> comparable
min x y =
    Basics.min x y


{-| Find the larger of two comparables.

    max 42 12345678 == 12345678

    max "abc" "xyz" == "xyz"

-}
max : comparable -> comparable -> comparable
max x y =
    Basics.max x y


{-| Compare any two comparable values. Comparable values include `String`,
`Char`, `Int`, `Float`, or a list or tuple containing comparable values. These
are also the only values that work as `Dict` keys or `Set` members.

    compare 3 4 == LT

    compare 4 4 == EQ

    compare 5 4 == GT

-}
compare : comparable -> comparable -> Order
compare =
    Basics.compare


{-| Represents the relative ordering of two things.
The relations are less than, equal to, and greater than.
-}
type alias Order =
    Basics.Order
