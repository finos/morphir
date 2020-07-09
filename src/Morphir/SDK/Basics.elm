module Morphir.SDK.Basics exposing (append)

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
