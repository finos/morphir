port module Morphir.Web.Editor exposing (..)

import Browser
import Element
import Html exposing (Html)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.FormatVersion.Codec exposing (decodeVersionedDistribution)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Type.DataCodec as DataCodec exposing (decodeData)
import Morphir.IR.Value exposing (RawValue, Value(..))
import Morphir.Visual.Theme as Theme exposing (Theme)
import Morphir.Visual.ValueEditor as ValueEditor



--MODEL


type alias Model =
    Result String ModelState


type alias ModelState =
    { ir : Distribution
    , theme : Theme
    , valueType : Type ()
    , editorState : ValueEditor.EditorState
    , encoder : RawValue -> Result String Encode.Value
    }



--MAIN


main : Program Decode.Value Model Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }



--INIT


init : Decode.Value -> ( Model, Cmd Msg )
init flags =
    case flags |> Decode.decodeValue decodeFlag of
        Ok flag ->
            let
                tpe : Type ()
                tpe =
                    Type.Reference () flag.entryPoint []

                distro : Distribution
                distro =
                    flag.distribution

                initEditorState : ValueEditor.EditorState
                initEditorState =
                    ValueEditor.initEditorState distro tpe flag.initialValue

                encoderResult : Result String (RawValue -> Result String Encode.Value)
                encoderResult =
                    DataCodec.encodeData distro tpe

                model : Model
                model =
                    encoderResult
                        |> Result.map
                            (\encoder ->
                                { ir = distro
                                , theme = Theme.fromConfig Nothing
                                , valueType = tpe
                                , editorState = initEditorState
                                , encoder = encoder
                                }
                            )
            in
            ( model
            , Cmd.none
            )

        Err error ->
            ( Err (Decode.errorToString error), reportError (Decode.errorToString error) )



--FLAGS


type alias Flags =
    { distribution : Distribution
    , entryPoint : FQName
    , initialValue : Maybe RawValue
    }



--MESSAGE


type Msg
    = UpdatedEditor ValueEditor.EditorState



--PORTS


port valueUpdated : Decode.Value -> Cmd msg


port reportError : String -> Cmd msg



--SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



--UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case model of
        Ok m ->
            case msg of
                UpdatedEditor editorState ->
                    case editorState.errorState of
                        Just error ->
                            ( model, reportError error )

                        Nothing ->
                            let
                                jsonResult : Result String Encode.Value
                                jsonResult =
                                    editorState.lastValidValue
                                        |> Maybe.map m.encoder
                                        |> Maybe.withDefault (Ok Encode.null)
                            in
                            case jsonResult of
                                Ok json ->
                                    ( Result.map (\mod -> { mod | editorState = editorState }) model
                                    , valueUpdated json
                                    )

                                Err error ->
                                    ( model, reportError error )

        Err error ->
            ( model, Cmd.none )



--VIEW


view : Model -> Html Msg
view model =
    case model of
        Ok { theme, ir, editorState, valueType } ->
            Element.layout [] (ValueEditor.view theme ir valueType UpdatedEditor editorState)

        Err error ->
            Html.text error


decodeFlag : Decode.Decoder Flags
decodeFlag =
    let
        decodeResultToFailure : Result String (Decoder a) -> Decoder a
        decodeResultToFailure result =
            case result of
                Ok decoder ->
                    decoder

                Err error ->
                    Decode.fail error
    in
    Decode.map2
        (\distribution fqn ->
            let
                tpe =
                    Type.Reference () fqn []
            in
            Decode.field "initialValue"
                (Decode.maybe
                    (decodeData distribution tpe
                        |> decodeResultToFailure
                    )
                )
                |> Decode.map (Flags distribution fqn)
        )
        (Decode.field "distribution" decodeVersionedDistribution)
        (Decode.field "entryPoint" Decode.string
            |> Decode.andThen
                (\str ->
                    case FQName.fromStringStrict str ":" of
                        Ok fQName ->
                            Decode.succeed fQName

                        Err error ->
                            Decode.fail error
                )
        )
        |> Decode.andThen identity
