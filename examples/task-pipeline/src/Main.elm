module Main exposing (greet)

{-| Example Morphir module for task pipeline demonstration.
-}


{-| Simple greeting function.
-}
greet : String -> String
greet name =
    "Hello, " ++ name ++ "!"
