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


module Morphir.SDK.Function exposing (identity, always, composeLeft, composeRight)

{-| Function helpers for Morphir:

@docs identity, always, composeLeft, composeRight

-}

-- FUNCTION HELPERS


{-| Function composition, passing results along in the suggested direction. For
example, the following code checks if the square root of a number is odd:

    not << isEven << sqrt

You can think of this operator as equivalent to the following:

    (g << f) == (\x -> g (f x))

So our example expands out to something like this:

    \n -> not (isEven (sqrt n))

-}
composeLeft : (b -> c) -> (a -> b) -> (a -> c)
composeLeft g f x =
    g (f x)


{-| Function composition, passing results along in the suggested direction. For
example, the following code checks if the square root of a number is odd:

    sqrt >> isEven >> not

-}
composeRight : (a -> b) -> (b -> c) -> (a -> c)
composeRight f g x =
    g (f x)


{-| Given a value, returns exactly the same value. This is called
[the identity function](https://en.wikipedia.org/wiki/Identity_function).
-}
identity : a -> a
identity x =
    Basics.identity x


{-| Create a function that _always_ returns the same value. Useful with
functions like `map`:

    List.map (always 0) [1,2,3,4,5] == [0,0,0,0,0]

    -- List.map (\_ -> 0) [1,2,3,4,5] == [0,0,0,0,0]
    -- always = (\x _ -> x)

-}
always : a -> b -> a
always a b =
    Basics.always a b
