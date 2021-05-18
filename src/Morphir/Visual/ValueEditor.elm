module Morphir.Visual.ValueEditor exposing (..)

import Dict exposing (Dict)
import Element exposing (Element, above, el, height, moveUp, none, padding, paddingXY, px, rgb, shrink, spacing, table, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font exposing (center)
import Element.Input as Input exposing (placeholder)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name exposing (Name)
import Morphir.IR.SDK.Basics as Basics
import Morphir.IR.SDK.String as Basics
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue)
import Morphir.Visual.Common exposing (nameToText)


type alias EditorState =
    { componentState : ComponentState
    , lastValidValue : Maybe RawValue
    , errorState : Maybe Error
    }


type ComponentState
    = TextBox String
    | BoolEditor (Maybe Bool)
    | RecordEditor (List ( Name, Type (), EditorState ))


type alias Error =
    String


initEditorState : IR -> Type () -> Maybe RawValue -> EditorState
initEditorState ir valueType maybeInitialValue =
    { componentState = initComponentState ir valueType maybeInitialValue
    , lastValidValue = maybeInitialValue
    , errorState = Nothing
    }


initComponentState : IR -> Type () -> Maybe RawValue -> ComponentState
initComponentState ir valueType maybeInitialValue =
    case valueType of
        Type.Record _ fieldTypes ->
            initRecordEditor ir fieldTypes maybeInitialValue

        _ ->
            if valueType == Basics.boolType () then
                initBoolEditor maybeInitialValue

            else
                case valueType of
                    Type.Reference _ fQName typeArgs ->
                        case ir |> IR.lookupTypeSpecification fQName of
                            Just typeSpec ->
                                case typeSpec of
                                    Type.TypeAliasSpecification typeParams typeExp ->
                                        initComponentState ir typeExp maybeInitialValue

                                    Type.OpaqueTypeSpecification typeParams ->
                                        initTextBox maybeInitialValue

                                    Type.CustomTypeSpecification typeParams constructors ->
                                        initTextBox maybeInitialValue

                            Nothing ->
                                initTextBox maybeInitialValue

                    _ ->
                        initTextBox maybeInitialValue


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


initBoolEditor : Maybe RawValue -> ComponentState
initBoolEditor maybeInitialValue =
    let
        isChecked =
            case maybeInitialValue of
                Just initialValue ->
                    case initialValue of
                        Value.Literal _ (BoolLiteral value) ->
                            Just value

                        _ ->
                            Nothing

                Nothing ->
                    Nothing
    in
    BoolEditor isChecked


initRecordEditor : IR -> List (Type.Field ()) -> Maybe RawValue -> ComponentState
initRecordEditor ir fieldTypes maybeInitialValue =
    let
        initialFieldValues : Dict Name RawValue
        initialFieldValues =
            case maybeInitialValue of
                Just (Value.Record _ fieldValues) ->
                    fieldValues |> Dict.fromList

                _ ->
                    Dict.empty
    in
    RecordEditor
        (fieldTypes
            |> List.map
                (\field ->
                    ( field.name
                    , field.tpe
                    , initEditorState ir field.tpe (initialFieldValues |> Dict.get field.name)
                    )
                )
        )


view : IR -> Type () -> (EditorState -> msg) -> EditorState -> Element msg
view ir valueType updateEditorState editorState =
    case editorState.componentState of
        TextBox currentText ->
            let
                baseStyle =
                    [ width (px 70)
                    , height shrink
                    , paddingXY 10 3
                    ]

                errorStyle =
                    case editorState.errorState of
                        Just errorMessage ->
                            [ Border.color (rgb 1 0 0)
                            , Border.width 2
                            , above
                                (el
                                    [ padding 5
                                    , Background.color (rgb 1 0.7 0.7)
                                    , moveUp 5
                                    ]
                                    (text errorMessage)
                                )
                            ]

                        Nothing ->
                            [ Border.width 2
                            ]
            in
            Input.text (baseStyle ++ errorStyle)
                { onChange =
                    \updatedText ->
                        let
                            valueResult : Result String RawValue
                            valueResult =
                                if valueType == Basics.stringType () then
                                    Ok (Value.Literal () (StringLiteral updatedText))

                                else if valueType == Basics.intType () then
                                    String.toInt updatedText
                                        |> Maybe.map (\int -> Value.Literal () (IntLiteral int))
                                        |> Result.fromMaybe "Expecting a whole number like 5 or -958"

                                else if valueType == Basics.floatType () then
                                    String.toFloat updatedText
                                        |> Maybe.map (\float -> Value.Literal () (FloatLiteral float))
                                        |> Result.fromMaybe "Expecting a number like 1, -3.14 or 100.56"

                                else
                                    Err (String.concat [ "Translating text into ", Debug.toString valueType, " is not supported" ])
                        in
                        if updatedText == "" then
                            updateEditorState
                                (initEditorState ir valueType Nothing)

                        else
                            updateEditorState
                                (applyResult valueResult
                                    { editorState
                                        | componentState = TextBox updatedText
                                    }
                                )
                , text = currentText
                , placeholder =
                    Just (placeholder [ center, paddingXY 0 1 ] (text "not set"))
                , label = Input.labelHidden ""
                }

        BoolEditor isChecked ->
            Input.radioRow
                [ spacing 10 ]
                { onChange =
                    \updatedIsChecked ->
                        updateEditorState
                            { editorState
                                | componentState = BoolEditor (Just updatedIsChecked)
                                , lastValidValue = Just (Value.Literal () (BoolLiteral updatedIsChecked))
                            }
                , options = [ Input.option True (text "yes"), Input.option False (text "no") ]
                , selected = isChecked
                , label = Input.labelHidden ""
                }

        RecordEditor fieldEditorStates ->
            table []
                { columns =
                    [ { header = none
                      , width = shrink
                      , view =
                            \( fieldName, _, _ ) ->
                                el [ paddingXY 10 5 ] (text (nameToText fieldName))
                      }
                    , { header = none
                      , width = shrink
                      , view =
                            \( fieldName, fieldType, fieldEditorState ) ->
                                el []
                                    (view ir
                                        fieldType
                                        (\newFieldEditorState ->
                                            updateEditorState
                                                { editorState
                                                    | componentState =
                                                        RecordEditor
                                                            (fieldEditorStates
                                                                |> List.map
                                                                    (\( currentFieldName, currentFieldType, currentFieldEditorState ) ->
                                                                        if fieldName == currentFieldName then
                                                                            ( currentFieldName, currentFieldType, newFieldEditorState )

                                                                        else
                                                                            ( currentFieldName, currentFieldType, currentFieldEditorState )
                                                                    )
                                                            )
                                                }
                                        )
                                        fieldEditorState
                                    )
                      }
                    ]
                , data = fieldEditorStates
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
