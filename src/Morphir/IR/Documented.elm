module Morphir.IR.Documented exposing (..)

{-| Tools to assign documentation to nodes in the IR.
-}


{-| Type that represents a documented value.
-}
type alias Documented a =
    { doc : String
    , value : a
    }


map : (a -> b) -> Documented a -> Documented b
map f { doc, value } =
    Documented doc (f value)
