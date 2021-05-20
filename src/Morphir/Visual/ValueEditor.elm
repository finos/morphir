module Morphir.Visual.ValueEditor exposing (..)

import Dict exposing (Dict)
import Element exposing (Element, above, below, centerY, column, el, explain, fill, height, html, htmlAttribute, moveDown, moveUp, none, padding, paddingXY, px, rgb, row, shrink, spacing, table, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Events as Events
import Element.Font exposing (center)
import Element.Input as Input exposing (placeholder)
import Html
import Html.Attributes
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name exposing (Name)
import Morphir.IR.SDK.Basics as Basics
import Morphir.IR.SDK.Char as Basics
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
    | CustomEditor String (Type.Constructors ()) (List ( Name, List ( Name, Type () ) ))


type alias Error =
    String


initEditorState : IR -> Type () -> Maybe RawValue -> EditorState
initEditorState ir valueType maybeInitialValue =
    let
        ( maybeError, componentState ) =
            initComponentState ir valueType maybeInitialValue
    in
    { componentState = componentState
    , lastValidValue = maybeInitialValue
    , errorState = maybeError
    }


initComponentState : IR -> Type () -> Maybe RawValue -> ( Maybe Error, ComponentState )
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
                                        initCustomEditor ir maybeInitialValue

                            Nothing ->
                                initTextBox maybeInitialValue

                    _ ->
                        initTextBox maybeInitialValue


initTextBox : Maybe RawValue -> ( Maybe Error, ComponentState )
initTextBox maybeInitialValue =
    case maybeInitialValue of
        Just initialValue ->
            case initialValue of
                Value.Literal _ (StringLiteral string) ->
                    ( Nothing, TextBox string )

                Value.Literal _ (CharLiteral char) ->
                    ( Nothing, TextBox (String.fromChar char) )

                Value.Literal _ (IntLiteral int) ->
                    ( Nothing, TextBox (String.fromInt int) )

                Value.Literal _ (FloatLiteral float) ->
                    ( Nothing, TextBox (String.fromFloat float) )

                _ ->
                    ( Just ("Cannot initialize editor with value: " ++ Debug.toString initialValue), TextBox "" )

        Nothing ->
            ( Nothing, TextBox "" )


initBoolEditor : Maybe RawValue -> ( Maybe Error, ComponentState )
initBoolEditor maybeInitialValue =
    case maybeInitialValue of
        Just initialValue ->
            case initialValue of
                Value.Literal _ (BoolLiteral value) ->
                    ( Nothing, BoolEditor (Just value) )

                _ ->
                    ( Just ("Cannot initialize editor with value: " ++ Debug.toString initialValue), BoolEditor Nothing )

        Nothing ->
            ( Nothing, BoolEditor Nothing )


initRecordEditor : IR -> List (Type.Field ()) -> Maybe RawValue -> ( Maybe Error, ComponentState )
initRecordEditor ir fieldTypes maybeInitialValue =
    let
        recordEditor initialFieldValues =
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
    in
    case maybeInitialValue of
        Just initialValue ->
            case initialValue of
                Value.Record _ fieldValues ->
                    ( Nothing, recordEditor (fieldValues |> Dict.fromList) )

                _ ->
                    ( Just ("Cannot initialize editor with value: " ++ Debug.toString initialValue), recordEditor Dict.empty )

        Nothing ->
            ( Nothing, recordEditor Dict.empty )


initCustomEditor : IR -> Maybe RawValue -> ( Maybe Error, ComponentState )
initCustomEditor ir maybeInitialValue =
    ( Nothing, CustomEditor "" Dict.empty [] )


view : IR -> Type () -> (EditorState -> msg) -> EditorState -> Element msg
view ir valueType updateEditorState editorState =
    case editorState.componentState of
        TextBox currentText ->
            let
                baseStyle =
                    [ width (px 70)
                    , height shrink
                    , paddingXY 10 3
                    , Events.onLoseFocus
                        (updateEditorState (initEditorState ir valueType editorState.lastValidValue))
                    ]

                errorStyle =
                    case editorState.errorState of
                        Just errorMessage ->
                            [ Border.color (rgb 1 0 0)
                            , Border.width 2
                            , below
                                (el
                                    [ padding 5
                                    , Background.color (rgb 1 0.7 0.7)
                                    , moveDown 5
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

                                else if valueType == Basics.charType () then
                                    String.uncons updatedText
                                        |> Result.fromMaybe "Expecting at least one character"
                                        |> Result.andThen
                                            (\( char, rest ) ->
                                                if String.isEmpty rest then
                                                    Ok (Value.Literal () (CharLiteral char))

                                                else
                                                    Err "Expecting a single character only"
                                            )

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
                [ paddingXY 10 5
                , spacing 10
                ]
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
            table
                [ width fill
                , height fill
                ]
                { columns =
                    [ { header = none
                      , width = shrink
                      , view =
                            \( fieldName, _, _ ) ->
                                row [ width fill ]
                                    [ el [ width fill, paddingXY 10 5 ] (text (nameToText fieldName))
                                    , el [ padding 5 ] (text ":")
                                    ]
                      }
                    , { header = none
                      , width = shrink
                      , view =
                            \( fieldName, fieldType, fieldEditorState ) ->
                                el
                                    [ width fill
                                    , height fill
                                    , centerY
                                    ]
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

        CustomEditor searchText allConstructors selectedConstructors ->
            column []
                [ Input.text
                    [ width (px 70)
                    , height shrink
                    , paddingXY 10 3
                    , htmlAttribute (Html.Attributes.list "custom")
                    ]
                    { onChange =
                        \updatedText ->
                            updateEditorState
                                { editorState
                                    | componentState = CustomEditor updatedText allConstructors selectedConstructors
                                }
                    , text = searchText
                    , placeholder =
                        Just (placeholder [ center, paddingXY 0 1 ] (text "not set"))
                    , label = Input.labelHidden ""
                    }
                , html
                    (Html.datalist [ Html.Attributes.id "custom" ]
                        [ Html.option [] [ Html.text "foo" ]
                        , Html.option [] [ Html.text "bar" ]
                        ]
                    )
                ]


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
