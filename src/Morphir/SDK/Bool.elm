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


module Morphir.SDK.Bool exposing (..)

{-| Boolean operations.

@docs Bool, true, false, not, and, or, xor

-}


{-| A “Boolean” value. It can either be `True` or `False`.

**Note:** Programmers coming from JavaScript, Java, etc. tend to reach for
boolean values way too often in Elm. Using a [union type][ut] is often clearer
and more reliable. You can learn more about this from Jeremy [here][jf] or
from Richard [here][rt].

[ut]: https://guide.elm-lang.org/types/union_types.html
[jf]: https://youtu.be/6TDKHGtAxeg?t=1m25s
[rt]: https://youtu.be/IcgmSRJHu_8?t=1m14s

-}
type alias Bool =
    Basics.Bool


{-| True
-}
true : Bool
true =
    True


{-| False
-}
false : Bool
false =
    False


{-| Negate a boolean value.

    not True == False

    not False == True

-}
not : Bool -> Bool
not =
    Basics.not


{-| The logical AND operator. `True` if both inputs are `True`.

    True && True == True

    True && False == False

    False && True == False

    False && False == False

**Note:** When used in the infix position, like `(left && right)`, the operator
short-circuits. This means if `left` is `False` we do not bother evaluating `right`
and just return `False` overall.

-}
and : Bool -> Bool -> Bool
and =
    (&&)


{-| The logical OR operator. `True` if one or both inputs are `True`.

    True || True == True

    True || False == True

    False || True == True

    False || False == False

**Note:** When used in the infix position, like `(left || right)`, the operator
short-circuits. This means if `left` is `True` we do not bother evaluating `right`
and just return `True` overall.

-}
or : Bool -> Bool -> Bool
or =
    (||)


{-| The exclusive-or operator. `True` if exactly one input is `True`.

    xor True True == False

    xor True False == True

    xor False True == True

    xor False False == False

-}
xor : Bool -> Bool -> Bool
xor =
    Basics.xor
