port module Morphir.Elm.DevCLI exposing (..)

import Json.Decode as Decode
import Json.Encode as Encode


port request : (Decode.Value -> msg) -> Sub msg


port respond : Encode.Value -> Cmd msg


main : Platform.Program () () Msg
main =
    Platform.worker
        { init = \_ -> ( (), Cmd.none )
        , update = update
        , subscriptions = subscriptions
        }


type alias Model =
    ()


type Msg
    = Request Decode.Value


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Request bodyJson ->
            let
                _ =
                    Debug.log "request body" (Encode.encode 4 bodyJson)
            in
            ( model, respond (Encode.string "Hi") )


subscriptions : Model -> Sub Msg
subscriptions model =
    request Request
