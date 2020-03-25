module Morphir.SDK.Basics exposing
    ( append
    , identity, always
    , composeLeft, composeRight
    )

{-| Mirror of the `Basics` module in `elm/core` with some modifications for Morphir:

  - Operators are replaced with named functions.
      - The Morphir Elm frontend maps operators to these named functions.
  - `Never` type and `never` value are excluded since business logic should never use these.
  - `<|` and `|>` operators are excluded since they are purely syntactic.
      - The Morphir Elm frontend replaces `<|` with simple function application and `|>` with function application wit
        reversed argument order.
  - Some functions excluded do to being too graphics specific:
      - degrees, radians, turns, toPolar, fromPolar


# Append Strings and Lists

@docs append


# Function Helpers

@docs identity, always, apL, apR, composeL, composeR

-}

-- APPEND


{-| Put two appendable things together. This includes strings and lists.

    "hello" ++ "world" == "helloworld"

    [ 1, 1, 2 ] ++ [ 3, 5, 8 ] == [ 1, 1, 2, 3, 5, 8 ]

-}
append : appendable -> appendable -> appendable
append =
    (++)



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
