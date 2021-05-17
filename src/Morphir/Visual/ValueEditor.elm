module Morphir.Visual.ValueEditor exposing (..)

import Element exposing (Element, height, none, paddingXY, px, shrink, text, width)
import Element.Input as Input exposing (placeholder)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.SDK.Basics as Basics
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue)


type alias EditorState =
    { componentState : ComponentState
    , lastValidValue : Maybe RawValue
    , errorState : Maybe Error
    }


type ComponentState
    = TextBox String


type alias Error =
    String


initEditorState : Type () -> Maybe RawValue -> EditorState
initEditorState valueType maybeInitialValue =
    { componentState =
        initTextBox maybeInitialValue
    , lastValidValue = maybeInitialValue
    , errorState = Nothing
    }


initTextBox : Maybe RawValue -> ComponentState
initTextBox maybeInitialValue =
    let
        text =
            case maybeInitialValue of
                Just initialValue ->
                    case initialValue of
                        Value.Literal _ (IntLiteral int) ->
                            String.fromInt int

                        Value.Literal _ (FloatLiteral float) ->
                            String.fromFloat float

                        _ ->
                            "error"

                Nothing ->
                    ""
    in
    TextBox text


view : Type () -> (EditorState -> msg) -> EditorState -> Element msg
view valueType updateEditorState editorState =
    case editorState.componentState of
        TextBox currentText ->
            Input.text
                [ width (px 70)
                , height shrink
                , paddingXY 10 3
                ]
                { onChange =
                    \updatedText ->
                        let
                            valueResult : Result String RawValue
                            valueResult =
                                if valueType == Basics.intType () then
                                    String.toInt updatedText
                                        |> Maybe.map (\int -> Value.Literal () (IntLiteral int))
                                        |> Result.fromMaybe "Expected an integer value"

                                else if valueType == Basics.floatType () then
                                    String.toFloat updatedText
                                        |> Maybe.map (\float -> Value.Literal () (FloatLiteral float))
                                        |> Result.fromMaybe "Expected a floating-point value"

                                else
                                    Err (String.concat [ "Translating text into ", Debug.toString valueType, " is not supported" ])
                        in
                        if updatedText == "" then
                            updateEditorState
                                (initEditorState valueType Nothing)

                        else
                            updateEditorState
                                (applyResult valueResult
                                    { editorState
                                        | componentState = TextBox updatedText
                                    }
                                )
                , text = currentText
                , placeholder =
                    Just (placeholder [] (text "not set"))
                , label = Input.labelHidden ""
                }


applyResult : Result String RawValue -> EditorState -> EditorState
applyResult valueResult editorState =
    { editorState
        | lastValidValue =
            case valueResult of
                Ok newValue ->
                    Just newValue

                Err _ ->
                    editorState.lastValidValue
        , errorState =
            case valueResult of
                Ok _ ->
                    Nothing

                Err error ->
                    Just error
    }
