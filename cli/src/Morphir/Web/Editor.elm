port module Morphir.Web.Editor exposing (..)

import Browser
import Element
import Html exposing (Html)
import Json.Decode as Decode exposing (Decoder, decodeString)
import Json.Encode as Encode
import Morphir.Codec exposing (decodeUnit, encodeUnit)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.Distribution.Codec exposing (decodeVersionedDistribution)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.FQName.Codec exposing (decodeFQName)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Type.Codec exposing (decodeType)
import Morphir.IR.Type.DataCodec exposing (decodeData)
import Morphir.IR.Value exposing (RawValue, Value(..))
import Morphir.IR.Value.Codec exposing (encodeValue)
import Morphir.Visual.Theme as Theme exposing (Theme)
import Morphir.Visual.ValueEditor as ValueEditor



--MODEL


type alias Model =
    Result String ModelState


type alias ModelState =
    { ir : IR
    , theme : Theme
    , valueType : Type ()
    , editorState : ValueEditor.EditorState
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
                tpe =
                    Type.Reference () flag.entryPoint []

                initEditorState =
                    ValueEditor.initEditorState (IR.fromDistribution flag.distribution) tpe flag.initialValue

                _ =
                    Debug.log "InitialValue" flag.initialValue
            in
            ( Ok
                { ir = IR.fromDistribution flag.distribution
                , theme = Theme.fromConfig Nothing
                , valueType = tpe
                , editorState = initEditorState
                }
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
        Ok _ ->
            case msg of
                UpdatedEditor editorState ->
                    case editorState.errorState of
                        Just a ->
                            let
                                err =
                                    Debug.log
                            in
                            ( model, Cmd.none )

                        Nothing ->
                            let
                                valueJson =
                                    editorState.lastValidValue
                                        |> Maybe.map (encodeValue encodeUnit encodeUnit)
                                        |> Maybe.withDefault Encode.null
                            in
                            ( model, valueUpdated valueJson )

        Err _ ->
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
                    (decodeData (IR.fromDistribution distribution) tpe
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
