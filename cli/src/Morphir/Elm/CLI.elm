port module Morphir.Elm.CLI exposing (main)

import Json.Decode as Decode
import Json.Encode as Encode


port input : (Decode.Value -> msg) -> Sub msg


port output : Encode.Value -> Cmd msg


type Msg
    = Input Decode.Value


main : Platform.Program () () Msg
main =
    Platform.worker
        { init = \_ -> ( (), Cmd.none )
        , update = update
        , subscriptions = \_ -> input Input
        }


update : Msg -> () -> ( (), Cmd Msg )
update msg model =
    case msg of
        Input jsonValue ->
            ( model, output (Decode.decodeValue Decode.value jsonValue |> Result.withDefault Encode.null) )
