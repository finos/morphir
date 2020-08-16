module Morphir.Reference.Model.Types exposing (..)

{-| Various examples of types for testing.
-}


{-| Alias referring to another type using a reference.
-}
type alias Quantity =
    Int


type Custom
    = CustomNoArg
    | CustomOneArg Bool
    | CustomTwoArg String Quantity


type alias FooBarBazRecord =
    { foo : String
    , bar : Bool
    , baz : Int
    }
