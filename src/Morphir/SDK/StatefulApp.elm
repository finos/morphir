module Morphir.SDK.StatefulApp exposing (..)


type alias StatefulApp c s e =
    { businessLogic : Maybe s -> c -> ( Maybe s, e ) }
