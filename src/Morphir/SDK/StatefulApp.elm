module Morphir.SDK.StatefulApp exposing (..)


type alias StatefulApp k c s e =
    { businessLogic : k -> Maybe s -> c -> ( k, Maybe s, e ) }
