module Types exposing (Flag)

{-| A simple boolean flag decoration type.

This decoration can be attached to any IR node to mark it with a boolean flag.
-}

{-| A simple boolean flag decoration.
-}
type alias Flag =
    Bool
