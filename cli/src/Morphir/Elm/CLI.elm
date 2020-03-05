port module Morphir.Elm.CLI exposing (main)

import Json.Decode as Decode
import Json.Encode as Encode


port input : (Decode.Value -> msg) -> Sub msg


port output : Encode.Value -> Cmd msg


type alias Flags =
    {}


type alias Model =
    {}


type Msg
    = Input Decode.Value


main : Platform.Program Flags Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = \_ -> input Input
        }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( {}, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Input jsonValue ->
            ( model, output (Decode.decodeValue Decode.value jsonValue |> Result.withDefault Encode.null) )
