module Morphir.Visual.ValueEditor exposing (EditorState, initEditorState, view)

{-| The purpose of this component is to display an editor that allows the user to edit a value of a certain type while
making sure that the value will be valid for that type.


# Usage

The component is designed to be integrated into an Elm application by:

  - Storing the `EditorState` in the host application's model.
  - Initializing the editor state using `initEditorState`.
  - Invoking `view` somewhere within the host application's `view` function to display the component while passing a
    message constructor to allow the editor to notify the host application about edits.
  - Handling the edit message in the `update` function and update the editor state in the model.

@docs EditorState, initEditorState, view


# Extending

This component only works for value types that it explicitly handles. The expectation is that over time we add support
for all possible Morphir types. To add a new type of editor you need to take the following steps:

  - Add a new constructor to the `ComponentState` type.
      - This constructor will be used to keep track of the state of the visual component used to edit the value so it
        should contain enough information (as arguments) to create the component from scratch.
  - Add a new branch to `initComponentState` to map the value type to the new component state.
  - Add a new case to `view` to display the editor.

-}

import Dict exposing (Dict)
import Element exposing (Element, below, centerY, column, el, fill, height, html, htmlAttribute, minimum, moveDown, padding, paddingXY, rgb, shrink, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Events as Events
import Element.Font exposing (center)
import Element.Input as Input exposing (placeholder)
import Html
import Html.Attributes
import Morphir.IR as IR exposing (IR)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path exposing (Path)
import Morphir.IR.SDK.Basics as Basics
import Morphir.IR.SDK.Char as Basics
import Morphir.IR.SDK.String as Basics
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue)
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.Components.FieldList as FieldList


{-| Type that represents the state of the value editor. It's made up of the following pieces of information:

  - `componentState`
      - The state of the visual component used to edit the value.
      - This could be as simple as text box or or as complex as a grid.
      - The type of visual component shown here depends entirely on the type of the value being edited.
  - `lastValidValue`
      - The component state can store values that are not valid for the value type being edited. For example you could
        have non-digit characters in a text box used to edit an integer value.
      - This field stores the last valid value that the editor contained in the past and makes it possible to revert back
        to a valid state when the user clicks away from an editor that's in an invalid state.
  - `errorState`
      - This field is used by the editor to communicate invalid states.

**Note:** It's tempting to think that an editor is either in a valid or an invalid state, never both so a `Result` would
be a better choice to keep track of the value. In reality we do want to keep the previous valid state even if the editor
goes into an error state so that we can recover from a half-done edit.

-}
type alias EditorState =
    { componentState : ComponentState
    , lastValidValue : Maybe RawValue
    , errorState : Maybe Error
    }


{-| The state of the visual component used to edit the value.

  - This could be as simple as text box or or as complex as a grid.
  - The type of visual component shown here depends entirely on the type of the value being edited.

-}
type ComponentState
    = TextEditor String
    | BoolEditor (Maybe Bool)
    | RecordEditor (Dict Name ( Type (), EditorState ))
    | CustomEditor String (Type.Constructors ()) (List ( Name, List ( Name, Type () ) )) Path Path


type alias Error =
    String


{-| This function is used by the hosting application to initialize the editor state. It takes the following inputs:

  - `ir` - This is used to look up additional type information when needed.
  - `valueType` - The type of the value being edited.
  - `maybeInitialValue` - Optional starting value for the editor.

-}
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


{-| Creates a component state with an optional error. It takes the following inputs:

  - `ir` - This is used to look up additional type information when needed.
  - `valueType` - The type of the value being edited.
  - `maybeInitialValue` - Optional starting value for the editor.

An error might be reported when the initial value being passed in is invalid for the given editor.

-}
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
                    Type.Reference _ fQName _ ->
                        case ir |> IR.lookupTypeSpecification fQName of
                            Just typeSpec ->
                                case typeSpec of
                                    Type.TypeAliasSpecification _ typeExp ->
                                        initComponentState ir typeExp maybeInitialValue

                                    Type.OpaqueTypeSpecification _ ->
                                        initTextEditor maybeInitialValue

                                    Type.CustomTypeSpecification _ constructors ->
                                        initCustomEditor ir fQName constructors maybeInitialValue

                            Nothing ->
                                initTextEditor maybeInitialValue

                    _ ->
                        initTextEditor maybeInitialValue


{-| Creates a component state for a text editor with an optional error.
-}
initTextEditor : Maybe RawValue -> ( Maybe Error, ComponentState )
initTextEditor maybeInitialValue =
    case maybeInitialValue of
        Just initialValue ->
            case initialValue of
                Value.Literal _ (StringLiteral string) ->
                    ( Nothing, TextEditor string )

                Value.Literal _ (CharLiteral char) ->
                    ( Nothing, TextEditor (String.fromChar char) )

                Value.Literal _ (IntLiteral int) ->
                    ( Nothing, TextEditor (String.fromInt int) )

                Value.Literal _ (FloatLiteral float) ->
                    ( Nothing, TextEditor (String.fromFloat float) )

                _ ->
                    ( Just ("Cannot initialize editor with value: " ++ Debug.toString initialValue), TextEditor "" )

        Nothing ->
            ( Nothing, TextEditor "" )


{-| Creates a component state for a boolean editor with an optional error.
-}
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


{-| Creates a component state for a record editor with an optional error.
-}
initRecordEditor : IR -> List (Type.Field ()) -> Maybe RawValue -> ( Maybe Error, ComponentState )
initRecordEditor ir fieldTypes maybeInitialValue =
    let
        recordEditor initialFieldValues =
            RecordEditor
                (fieldTypes
                    |> List.map
                        (\field ->
                            ( field.name
                            , ( field.tpe
                              , initEditorState ir field.tpe (initialFieldValues |> Dict.get field.name)
                              )
                            )
                        )
                    |> Dict.fromList
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


{-| Creates a component state for a custom type editor with an optional error.
-}
initCustomEditor : IR -> FQName -> Type.Constructors () -> Maybe RawValue -> ( Maybe Error, ComponentState )
initCustomEditor _ ( packageName, moduleName, _ ) constructors _ =
    ( Nothing, CustomEditor "" constructors [] packageName moduleName )


{-| Display the editor. It takes the following inputs:

  - `ir` - This is used to look up additional type information when needed.
  - `valueType` - The type of the value being edited.
  - `updateEditorState` - Function to create the message that will be sent by this component during edits.
  - `editorState` - The current editor state.

-}
view : IR -> Type () -> (EditorState -> msg) -> EditorState -> Element msg
view ir valueType updateEditorState editorState =
    case editorState.componentState of
        TextEditor currentText ->
            let
                baseStyle =
                    [ width (fill |> minimum 80)
                    , height fill
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
                            valueResult : Type () -> Result String RawValue
                            valueResult tpe =
                                if tpe == Basics.stringType () then
                                    Ok (Value.Literal () (StringLiteral updatedText))

                                else if tpe == Basics.charType () then
                                    String.uncons updatedText
                                        |> Result.fromMaybe "Expecting at least one character"
                                        |> Result.andThen
                                            (\( char, rest ) ->
                                                if String.isEmpty rest then
                                                    Ok (Value.Literal () (CharLiteral char))

                                                else
                                                    Err "Expecting a single character only"
                                            )

                                else if tpe == Basics.intType () then
                                    String.toInt updatedText
                                        |> Maybe.map (\int -> Value.Literal () (IntLiteral int))
                                        |> Result.fromMaybe "Expecting a whole number like 5 or -958"

                                else if tpe == Basics.floatType () then
                                    String.toFloat updatedText
                                        |> Maybe.map (\float -> Value.Literal () (FloatLiteral float))
                                        |> Result.fromMaybe "Expecting a number like 1, -3.14 or 100.56"

                                else
                                    Err (String.concat [ "Translating text into '", Type.toString valueType, "' is not supported" ])
                        in
                        if updatedText == "" then
                            updateEditorState
                                (initEditorState ir valueType Nothing)

                        else
                            updateEditorState
                                (applyResult (valueResult (IR.resolveType valueType ir))
                                    { editorState
                                        | componentState = TextEditor updatedText
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
            el
                [ padding 7
                , Background.color (rgb 0.7 0.8 0.9)
                , Border.rounded 7
                ]
                (FieldList.view
                    (fieldEditorStates
                        |> Dict.toList
                        |> List.map
                            (\( fieldName, ( fieldType, fieldEditorState ) ) ->
                                ( fieldName
                                , el
                                    [ width fill
                                    , height fill
                                    , centerY
                                    ]
                                    (view ir
                                        fieldType
                                        (\newFieldEditorState ->
                                            let
                                                newFieldEditorStates : Dict Name ( Type (), EditorState )
                                                newFieldEditorStates =
                                                    fieldEditorStates
                                                        |> Dict.insert fieldName ( fieldType, newFieldEditorState )

                                                recordResult : Result String RawValue
                                                recordResult =
                                                    newFieldEditorStates
                                                        |> Dict.toList
                                                        |> List.foldr
                                                            (\( nextFieldName, ( _, nextFieldEditorState ) ) fieldsResultSoFar ->
                                                                fieldsResultSoFar
                                                                    |> Result.andThen
                                                                        (\fieldsSoFar ->
                                                                            editorStateToRawValueResult nextFieldEditorState
                                                                                |> Result.map
                                                                                    (\maybeNextFieldValue ->
                                                                                        case maybeNextFieldValue of
                                                                                            Just nextFieldValue ->
                                                                                                ( nextFieldName, nextFieldValue ) :: fieldsSoFar

                                                                                            Nothing ->
                                                                                                fieldsSoFar
                                                                                    )
                                                                        )
                                                            )
                                                            (Ok [])
                                                        |> Result.map (Value.Record ())
                                            in
                                            updateEditorState
                                                (applyResult recordResult
                                                    { editorState
                                                        | componentState =
                                                            RecordEditor
                                                                newFieldEditorStates
                                                    }
                                                )
                                        )
                                        fieldEditorState
                                    )
                                )
                            )
                    )
                )

        CustomEditor searchText allConstructors selectedConstructors packageName moduleName ->
            let
                dataListID =
                    case valueType of
                        Type.Reference _ fQName _ ->
                            FQName.toString fQName

                        _ ->
                            ""
            in
            column [ width fill ]
                [ Input.text
                    [ width fill
                    , height shrink
                    , paddingXY 10 3
                    , htmlAttribute (Html.Attributes.list dataListID)
                    ]
                    { onChange =
                        \updatedText ->
                            let
                                constructorResult : Result String RawValue
                                constructorResult =
                                    Ok (Value.Constructor () ( packageName, moduleName, Name.fromString updatedText ))
                            in
                            updateEditorState
                                (applyResult constructorResult
                                    { editorState
                                        | componentState = CustomEditor updatedText allConstructors selectedConstructors packageName moduleName
                                    }
                                )
                    , text = searchText
                    , placeholder =
                        Just (placeholder [ center, paddingXY 0 1 ] (text "not set"))
                    , label = Input.labelHidden ""
                    }
                , html
                    (Html.datalist [ Html.Attributes.id dataListID ]
                        (allConstructors
                            |> Dict.toList
                            |> List.map
                                (\( constructorName, _ ) ->
                                    Html.option [] [ Html.text (nameToText constructorName) ]
                                )
                        )
                    )
                ]


{-| Utility function to apply the result of an edit to the editor state using the following logic:

  - If the result is `Ok` it
      - updates the `lastValidValue` to the new one and
      - clears out the error state
  - If the result is `Err` it
      - keeps the current `lastValidValue` and
      - updates the error state to the error

-}
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


editorStateToRawValueResult : EditorState -> Result String (Maybe RawValue)
editorStateToRawValueResult editorState =
    case editorState.errorState of
        Just error ->
            Err error

        Nothing ->
            Ok editorState.lastValidValue
