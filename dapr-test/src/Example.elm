module Example exposing (..)

import Int exposing (Int)


type alias StatefulApp k c s e =
    { businessLogic : k -> Maybe s -> c -> ( k, Maybe s, e ) }


type alias App =
    StatefulApp Int Int Int Int


app : App
app =
    StatefulApp logic


logic : Int -> Maybe Int -> Int -> ( Int, Maybe Int, Int )
logic key state event =
    case state of
        Just s ->
            ( key, Just (s + event), s + event )

        Nothing ->
            ( key, Just event, event )
