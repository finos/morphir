module Morphir.SDK.StatefulApp exposing (StatefulApp)

{-| Utilities for modeling stateful applications.

@docs StatefulApp

-}


{-| Type that represents a stateful application.
-}
type alias StatefulApp k c s e =
    { businessLogic : k -> Maybe s -> c -> ( k, Maybe s, e ) }
