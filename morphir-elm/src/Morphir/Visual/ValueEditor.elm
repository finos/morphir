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

import Array exposing (Array)
import Dict exposing (Dict)
import Element
    exposing
        ( Element
        , alignBottom
        , alignTop
        , below
        , centerY
        , column
        , el
        , fill
        , height
        , html
        , inFront
        , moveDown
        , moveLeft
        , moveUp
        , none
        , onRight
        , padding
        , paddingEach
        , paddingXY
        , rgb
        , rgba
        , row
        , spacing
        , table
        , text
        , width
        , centerX
        , shrink
        , minimum
        , maximum
        )
import Element.Background as Background
import Element.Border as Border
import Element.Events as Events
import Element.Font as Font exposing (center)
import Element.Input as Input exposing (placeholder)
import Morphir.Elm.Frontend as Frontend
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Basics as Basics
import Morphir.IR.SDK.Char as Basics
import Morphir.IR.SDK.Decimal as Decimal
import Morphir.IR.SDK.Dict as SDKDict
import Morphir.IR.SDK.LocalDate exposing (fromISO)
import Morphir.IR.SDK.String as Basics
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, Value(..))
import Morphir.SDK.Decimal as Decimal
import Morphir.SDK.LocalDate as LocalDate exposing (toISOString)
import Morphir.SDK.ResultList as ListOfResults
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.Components.DatePickerComponent as DatePicker
import Morphir.Visual.Components.FieldList as FieldList
import Morphir.Visual.Components.InputComponent as InputComponent
import Morphir.Visual.Components.Picklist as Picklist
import Morphir.Visual.Theme as Theme exposing (Theme, scaled)
import Svg
import Svg.Attributes
import Morphir.Visual.Theme as Theme


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
    , defaultValueCheckbox : DefaultValueCheckbox
    }


type alias DefaultValueCheckbox =
    { show : Bool
    , checked : Bool
    }


{-| The state of the visual component used to edit the value.

  - This could be as simple as text box or or as complex as a grid.
  - The type of visual component shown here depends entirely on the type of the value being edited.

-}
type ComponentState
    = TextEditor String
    | BoolEditor (Maybe Bool)
    | RecordEditor (Dict Name ( Type (), EditorState ))
    | CustomTypeEditor FQName (Type.Constructors ()) CustomTypeEditorState
    | MaybeEditor (Type ()) (Maybe EditorState)
    | ListEditor (Type ()) (List EditorState)
    | GridEditor (List ( Name, Type () )) (List (Array EditorState))
    | DictEditor ( Type (), Type () ) (List ( EditorState, EditorState ))
    | GenericEditor String
    | LocalDateEditor DatePicker.DatePickerState


type alias CustomTypeEditorState =
    { constructorPicklistState : Picklist.State (Type.Constructor ())
    , argumentEditorStates : Dict Name ( Type (), EditorState )
    }


type alias Error =
    String


type alias TypeCases a =
    { maybe : a
    , list : a
    , dict : a
    , record : a
    , default : a
    }


handleTypeCases : TypeCases a -> Type () -> a
handleTypeCases typeCases valueType =
    case valueType of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "maybe" ] ) [ _ ] ->
            typeCases.maybe

        -- if a value that is a List is not set then treat it as empty list
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) [ _ ] ->
            typeCases.list

        -- if a value that is a Dict is not set then treat it as empty Dict
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "dict" ] ], [ "dict" ] ) [ _, _ ] ->
            typeCases.dict

        Type.Record _ _ ->
            typeCases.record

        _ ->
            typeCases.default


{-| This function is used by the hosting application to initialize the editor state. It takes the following inputs:

  - `ir` - This is used to look up additional type information when needed.
  - `valueType` - The type of the value being edited.
  - `maybeInitialValue` - Optional starting value for the editor.

-}
initEditorState : Distribution -> Type () -> Maybe RawValue -> EditorState
initEditorState ir valueType maybeInitialValue =
    let
        adjustedInitialValue : Maybe RawValue
        adjustedInitialValue =
            case maybeInitialValue of
                Nothing ->
                    handleTypeCases
                        { maybe = Just (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ))
                        , list = Just (Value.List () [])
                        , dict = Just (SDKDict.fromListValue () (Value.List () []))
                        , record = maybeInitialValue
                        , default = maybeInitialValue
                        }
                        valueType

                _ ->
                    maybeInitialValue

        ( maybeError, componentState ) =
            initComponentState ir valueType adjustedInitialValue

        defaultValueCheckbox =
            if valueType == Basics.stringType () then
                { show = True, checked = False }

            else
                { show = False, checked = False }
    in
    { componentState = componentState
    , lastValidValue = adjustedInitialValue
    , errorState = maybeError
    , defaultValueCheckbox = defaultValueCheckbox
    }


{-| Creates a component state with an optional error. It takes the following inputs:

  - `ir` - This is used to look up additional type information when needed.
  - `valueType` - The type of the value being edited.
  - `maybeInitialValue` - Optional starting value for the editor.

An error might be reported when the initial value being passed in is invalid for the given editor.

-}
initComponentState : Distribution -> Type () -> Maybe RawValue -> ( Maybe Error, ComponentState )
initComponentState ir valueType maybeInitialValue =
    let
        textEditorTypes : List (Type ())
        textEditorTypes =
            [ Basics.intType (), Basics.stringType (), Basics.charType (), Basics.floatType (), Decimal.decimalType () ]
    in
    case valueType of
        Type.Record _ fieldTypes ->
            initRecordEditor ir fieldTypes maybeInitialValue

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "maybe" ] ) [ itemType ] ->
            initMaybeEditor ir itemType maybeInitialValue

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) [ itemType ] ->
            initListEditor ir itemType maybeInitialValue

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "dict" ] ], [ "dict" ] ) [ dictKeyType, dictValueType ] ->
            initDictEditor ir dictKeyType dictValueType maybeInitialValue

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "local", "date" ] ], [ "local", "date" ] ) [] ->
            initLocalDateEditor maybeInitialValue

        _ ->
            if valueType == Basics.boolType () then
                initBoolEditor maybeInitialValue

            else if textEditorTypes |> List.member valueType then
                initTextEditor maybeInitialValue

            else
                case valueType of
                    Type.Reference _ fQName _ ->
                        case ir |> Distribution.lookupTypeSpecification fQName of
                            Just typeSpec ->
                                case typeSpec of
                                    Type.TypeAliasSpecification _ typeExp ->
                                        initComponentState ir typeExp maybeInitialValue

                                    Type.OpaqueTypeSpecification _ ->
                                        initTextEditor maybeInitialValue

                                    Type.CustomTypeSpecification _ constructors ->
                                        initCustomEditor ir fQName constructors maybeInitialValue

                                    Type.DerivedTypeSpecification _ config ->
                                        initComponentState ir config.baseType maybeInitialValue

                            Nothing ->
                                initGenericEditor maybeInitialValue

                    _ ->
                        initGenericEditor maybeInitialValue


initGenericEditor : Maybe RawValue -> ( Maybe Error, ComponentState )
initGenericEditor maybeInitialValue =
    case maybeInitialValue of
        Just initialValue ->
            ( Nothing, GenericEditor (initialValue |> Value.toString) )

        Nothing ->
            ( Nothing, GenericEditor "" )


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

                Value.Literal _ (WholeNumberLiteral int) ->
                    ( Nothing, TextEditor (String.fromInt int) )

                Value.Literal _ (FloatLiteral float) ->
                    ( Nothing, TextEditor (String.fromFloat float) )

                Value.Literal _ (DecimalLiteral decimal) ->
                    ( Nothing, TextEditor (Decimal.toString decimal) )

                _ ->
                    ( Nothing, TextEditor (initialValue |> Value.toString) )

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
initRecordEditor : Distribution -> List (Type.Field ()) -> Maybe RawValue -> ( Maybe Error, ComponentState )
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
                    ( Nothing, recordEditor fieldValues )

                _ ->
                    ( Just ("Cannot initialize editor with value: " ++ Debug.toString initialValue), recordEditor Dict.empty )

        Nothing ->
            ( Nothing, recordEditor Dict.empty )


{-| Creates a component state for a custom type editor with an optional error.
-}
initCustomEditor : Distribution -> FQName -> Type.Constructors () -> Maybe RawValue -> ( Maybe Error, ComponentState )
initCustomEditor ir fqn constructors maybeSelected =
    let
        findConstructor : Name -> Maybe (Type.Constructor ())
        findConstructor ctorNameToFind =
            constructors
                |> Dict.toList
                |> List.filter
                    (\( ctorName, _ ) ->
                        ctorName == ctorNameToFind
                    )
                |> List.head

        emptyState : ( Maybe Error, ComponentState )
        emptyState =
            ( Nothing, CustomTypeEditor fqn constructors (CustomTypeEditorState (Picklist.init Nothing) Dict.empty) )
    in
    case maybeSelected of
        Just (Value.Constructor _ ( _, _, selectedName )) ->
            ( Nothing, CustomTypeEditor fqn constructors (CustomTypeEditorState (Picklist.init (findConstructor selectedName)) Dict.empty) )

        Just (Value.Apply _ fun lastArg) ->
            case Value.uncurryApply fun lastArg of
                ( Value.Constructor _ ( _, _, selectedName ), argValues ) ->
                    case findConstructor selectedName of
                        Just (( _, selectedConstructorArgs ) as selectedConstructor) ->
                            let
                                argumentEditorStates : Dict Name ( Type (), EditorState )
                                argumentEditorStates =
                                    Dict.fromList
                                        (List.map2
                                            (\( argName, argType ) argValue ->
                                                ( argName, ( argType, initEditorState ir argType (Just argValue) ) )
                                            )
                                            selectedConstructorArgs
                                            argValues
                                        )
                            in
                            ( Nothing, CustomTypeEditor fqn constructors (CustomTypeEditorState (Picklist.init (Just selectedConstructor)) argumentEditorStates) )

                        _ ->
                            emptyState

                _ ->
                    emptyState

        _ ->
            emptyState


{-| Creates a component state for a optional values.
-}
initMaybeEditor : Distribution -> Type () -> Maybe RawValue -> ( Maybe Error, ComponentState )
initMaybeEditor ir itemType maybeInitialValue =
    case maybeInitialValue of
        Just initialValue ->
            case initialValue of
                Value.Apply _ (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) value ->
                    ( Nothing, MaybeEditor itemType (Just (initEditorState ir itemType (Just value))) )

                Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ) ->
                    ( Nothing, MaybeEditor itemType (Just (initEditorState ir itemType Nothing)) )

                _ ->
                    ( Just ("Cannot initialize editor with value: " ++ Debug.toString initialValue), MaybeEditor itemType Nothing )

        Nothing ->
            ( Nothing, MaybeEditor itemType (Just (initEditorState ir itemType Nothing)) )


{-| Creates a component state for a list values.
-}
initListEditor : Distribution -> Type () -> Maybe RawValue -> ( Maybe Error, ComponentState )
initListEditor ir itemType maybeInitialValue =
    case ir |> Distribution.resolveType itemType of
        Type.Record _ fieldTypes ->
            let
                columnTypes : List ( Name, Type () )
                columnTypes =
                    fieldTypes
                        |> List.map
                            (\field ->
                                ( field.name, field.tpe )
                            )
            in
            case maybeInitialValue of
                Just initialValue ->
                    case initialValue of
                        Value.List _ records ->
                            ( Nothing
                            , GridEditor columnTypes
                                (records
                                    |> List.map
                                        (\record ->
                                            case record of
                                                Value.Record _ fieldValues ->
                                                    columnTypes
                                                        |> List.map
                                                            (\( columnName, columnType ) ->
                                                                initEditorState ir columnType (fieldValues |> Dict.get columnName)
                                                            )
                                                        |> Array.fromList

                                                _ ->
                                                    [ initEditorState ir itemType (Just record) ]
                                                        |> Array.fromList
                                        )
                                )
                            )

                        _ ->
                            ( Just ("Cannot initialize editor with value: " ++ Debug.toString initialValue), GridEditor columnTypes [] )

                Nothing ->
                    ( Nothing, GridEditor columnTypes [] )

        _ ->
            case maybeInitialValue of
                Just initialValue ->
                    case initialValue of
                        Value.List _ items ->
                            ( Nothing, ListEditor itemType (items |> List.map (\item -> initEditorState ir itemType (Just item))) )

                        _ ->
                            ( Just ("Cannot initialize editor with value: " ++ Debug.toString initialValue), ListEditor itemType [] )

                Nothing ->
                    ( Nothing, ListEditor itemType [] )


{-| Creates a component state for a list values.
-}
initDictEditor : Distribution -> Type () -> Type () -> Maybe RawValue -> ( Maybe Error, ComponentState )
initDictEditor ir dictKeyType dictValueType maybeInitialValue =
    case maybeInitialValue of
        Just initialValue ->
            case initialValue of
                Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "dict" ] ], [ "from", "list" ] )) (Value.List _ items) ->
                    let
                        editorResult =
                            items
                                |> List.map
                                    (\item ->
                                        case item of
                                            Value.Tuple _ [ itemKey, itemValue ] ->
                                                Ok
                                                    ( initEditorState ir dictKeyType (Just itemKey)
                                                    , initEditorState ir dictValueType (Just itemValue)
                                                    )

                                            _ ->
                                                Err ("Invalid Dict entry: " ++ Debug.toString item)
                                    )
                                |> ListOfResults.keepFirstError
                    in
                    case editorResult of
                        Ok editors ->
                            ( Nothing, DictEditor ( dictKeyType, dictValueType ) editors )

                        Err error ->
                            ( Just error, DictEditor ( dictKeyType, dictValueType ) [] )

                _ ->
                    ( Just ("Cannot initialize editor with value: " ++ Debug.toString initialValue), DictEditor ( dictKeyType, dictValueType ) [] )

        Nothing ->
            ( Nothing, DictEditor ( dictKeyType, dictValueType ) [] )


initLocalDateEditor : Maybe RawValue -> ( Maybe Error, ComponentState )
initLocalDateEditor maybeInitialValue =
    case maybeInitialValue of
        Just initialValue ->
            case initialValue of
                Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "local", "date" ] ], [ "from", "i", "s", "o" ] )) (Value.Literal () (StringLiteral dateString)) ->
                    ( Nothing, LocalDateEditor (DatePicker.initState (LocalDate.fromISO dateString)) )

                _ ->
                    ( Just ("Cannot initialize editor with value: " ++ Debug.toString initialValue), LocalDateEditor (DatePicker.initState Nothing) )

        Nothing ->
            ( Nothing, LocalDateEditor (DatePicker.initState Nothing) )


{-| Display the editor. It takes the following inputs:

  - `theme` - This is used for styling the component.
  - `ir` - This is used to look up additional type information when needed.
  - `valueType` - The type of the value being edited.
  - `updateEditorState` - Function to create the message that will be sent by this component during edits.
  - `editorState` - The current editor state.

-}
view : Theme -> Distribution -> Type () -> (EditorState -> msg) -> EditorState -> Element msg
view theme ir valueType updateEditorState editorState =
    let
        baseStyle : List (Element.Attribute msg)
        baseStyle =
            [ width (fill |> minimum (scaled 12 theme) |> maximum (scaled 20 theme))
            , height fill
            , Events.onLoseFocus
                (updateEditorState (initEditorState ir valueType editorState.lastValidValue))
            ]

        labelStyle : List (Element.Attr () msg)
        labelStyle =
            [ centerY
            , centerX
            , paddingEach { top = 5, bottom = 5, right = 10, left = 0 }
            , width (shrink |> minimum (Theme.scaled 10 theme) |> maximum (Theme.scaled 15 theme))
            , Font.italic
            ]
    in
    case editorState.componentState of
        TextEditor currentText ->
            let
                iconLabel tpe =
                    if tpe == Basics.stringType () then
                        "text"

                    else if tpe == Basics.charType () then
                        "one char."

                    else if tpe == Basics.intType () then
                        "integer"

                    else if tpe == Basics.floatType () then
                        "real num."

                    else if tpe == Decimal.decimalType () then
                        "decimal"

                    else
                        "?"
            in
            row [ width fill, spacing 5 ]
                [ InputComponent.textInput theme
                    baseStyle
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
                                            |> Maybe.map (\int -> Value.Literal () (WholeNumberLiteral int))
                                            |> Result.fromMaybe "Expecting a whole number like 5 or -958"

                                    else if tpe == Basics.floatType () then
                                        String.toFloat updatedText
                                            |> Maybe.map (\float -> Value.Literal () (FloatLiteral float))
                                            |> Result.fromMaybe "Expecting a number like 1, -3.14 or 100.56"

                                    else if tpe == Decimal.decimalType () then
                                        Decimal.fromString updatedText
                                            |> Maybe.map (\dec -> Value.Literal () (DecimalLiteral dec))
                                            |> Result.fromMaybe "Expecting a decimal number"

                                    else
                                        updatedText
                                            |> Frontend.mapValueToFile ir tpe
                                            |> Result.andThen
                                                (\sourceFileIR ->
                                                    let
                                                        packageName =
                                                            Path.fromString "My.Package"

                                                        moduleName =
                                                            Path.fromString "A"

                                                        localName =
                                                            Name.fromString "fooFunction"
                                                    in
                                                    case sourceFileIR |> Distribution.lookupValueDefinition ( packageName, moduleName, localName ) of
                                                        Just valDef ->
                                                            Ok (valDef.body |> Value.toRawValue)

                                                        Nothing ->
                                                            Err "Function name Not found"
                                                )
                            in
                            if updatedText == "" then
                                updateEditorState
                                    (initEditorState ir valueType Nothing)

                            else
                                updateEditorState
                                    (applyResult (valueResult (Distribution.resolveType valueType ir))
                                        { editorState
                                            | componentState = TextEditor updatedText
                                            , defaultValueCheckbox = { show = editorState.defaultValueCheckbox.show, checked = False }
                                        }
                                    )
                    , text = currentText
                    , placeholder =
                        Just (placeholder [ center, paddingXY 0 1 ] (text "not set"))
                    , label = Input.labelLeft labelStyle (text <| iconLabel (Distribution.resolveType valueType ir))
                    }
                    editorState.errorState
                , if editorState.defaultValueCheckbox.show then
                    InputComponent.checkBox theme
                        [ center, width shrink ]
                        { label = Input.labelRight (labelStyle ++ [ Background.color <| rgba 0 0 0 0 ]) (text "empty (\"\")")
                        , checked = editorState.defaultValueCheckbox.checked
                        , onChange =
                            \updatedIsChecked ->
                                updateEditorState
                                    (applyResult ((\_ -> Ok (Value.Literal () (StringLiteral ""))) (Distribution.resolveType valueType ir))
                                        { editorState
                                            | componentState = TextEditor ""
                                            , defaultValueCheckbox = { show = True, checked = updatedIsChecked }
                                        }
                                    )
                        }

                  else
                    none
                ]

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
                , label = Input.labelLeft labelStyle (text "bool")
                }

        RecordEditor fieldEditorStates ->
            row [] <|
                [ el [ Font.italic, paddingXY 10 5 ] (text "record")
                , el
                    [ padding <| Theme.largePadding theme
                    , Background.color theme.colors.brandPrimaryLight
                    , Theme.borderRounded theme
                    ]
                    (FieldList.view theme
                        (fieldEditorStates
                            |> Dict.toList
                            |> List.map
                                (\( fieldName, ( fieldType, fieldEditorState ) ) ->
                                    ( fieldName
                                    , el
                                        [ height fill
                                        , centerY
                                        ]
                                        (view theme
                                            ir
                                            fieldType
                                            (\newFieldEditorState ->
                                                let
                                                    newFieldEditorStates : Dict Name ( Type (), EditorState )
                                                    newFieldEditorStates =
                                                        fieldEditorStates
                                                            |> Dict.insert fieldName ( fieldType, newFieldEditorState )

                                                    allFieldsAreEmpty : Bool
                                                    allFieldsAreEmpty =
                                                        newFieldEditorStates
                                                            |> Dict.values
                                                            |> List.filterMap
                                                                (\( _, nextFieldEditorState ) ->
                                                                    case editorStateToRawValueResult nextFieldEditorState of
                                                                        Ok (Just value) ->
                                                                            Just value

                                                                        _ ->
                                                                            Nothing
                                                                )
                                                            |> List.isEmpty

                                                    recordResult : Result String RawValue
                                                    recordResult =
                                                        newFieldEditorStates
                                                            |> Dict.toList
                                                            |> List.foldr
                                                                (\( nextFieldName, ( nextFieldType, nextFieldEditorState ) ) fieldsResultSoFar ->
                                                                    fieldsResultSoFar
                                                                        |> Result.andThen
                                                                            (\fieldsSoFar ->
                                                                                editorStateToRawValueResult nextFieldEditorState
                                                                                    |> Result.andThen
                                                                                        (\maybeNextFieldValue ->
                                                                                            case maybeNextFieldValue of
                                                                                                Just nextFieldValue ->
                                                                                                    Ok <| ( nextFieldName, nextFieldValue ) :: fieldsSoFar

                                                                                                Nothing ->
                                                                                                    case nextFieldType of
                                                                                                        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "maybe" ] ) _ ->
                                                                                                            Ok <| ( nextFieldName, Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ) ) :: fieldsSoFar

                                                                                                        _ ->
                                                                                                            Err <| "Missing field value: " ++ Name.toCamelCase nextFieldName
                                                                                        )
                                                                            )
                                                                )
                                                                (Ok [])
                                                            |> Result.map (Dict.fromList >> Value.Record ())
                                                in
                                                if allFieldsAreEmpty then
                                                    updateEditorState
                                                        { editorState
                                                            | componentState =
                                                                RecordEditor
                                                                    newFieldEditorStates
                                                            , lastValidValue =
                                                                Nothing
                                                            , errorState =
                                                                Nothing
                                                        }

                                                else
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
                ]

        CustomTypeEditor fqn constructors customEditorState ->
            viewCustomTypeEditor theme labelStyle ir updateEditorState editorState fqn constructors customEditorState

        MaybeEditor itemType maybeItemEditorState ->
            let
                itemEditor itemEditorState =
                    view theme
                        ir
                        itemType
                        (\newItemEditorState ->
                            let
                                maybeValueResult : Result Error RawValue
                                maybeValueResult =
                                    case newItemEditorState.errorState of
                                        Just error ->
                                            Err error

                                        Nothing ->
                                            case newItemEditorState.lastValidValue of
                                                Just itemValue ->
                                                    Ok (Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) itemValue)

                                                Nothing ->
                                                    Ok (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ))
                            in
                            updateEditorState
                                (applyResult maybeValueResult
                                    { editorState
                                        | componentState = MaybeEditor itemType (Just newItemEditorState)
                                    }
                                )
                        )
                        itemEditorState
            in
            row [] <|
                [ el [ centerY, paddingXY 0 5, Font.italic ] (text "optional ")
                , itemEditor
                    (maybeItemEditorState
                        |> Maybe.withDefault (initEditorState ir itemType Nothing)
                    )
                ]

        ListEditor itemType itemEditorStates ->
            let
                set : Int -> a -> List a -> List a
                set index item list =
                    List.concat
                        [ List.take index list
                        , [ item ]
                        , List.drop (index + 1) list
                        ]

                insert : Int -> a -> List a -> List a
                insert index item list =
                    List.concat
                        [ List.take index list
                        , [ item ]
                        , List.drop index list
                        ]

                remove : Int -> List a -> List a
                remove index list =
                    List.concat
                        [ List.take index list
                        , List.drop (index + 1) list
                        ]

                defaultItemEditorState =
                    initEditorState ir itemType Nothing

                updateState : List EditorState -> msg
                updateState itemStates =
                    let
                        listValueResult : Result Error RawValue
                        listValueResult =
                            itemStates
                                |> List.filterMap
                                    (\nextItemEditorState ->
                                        editorStateToRawValueResult nextItemEditorState
                                            |> Result.toMaybe
                                            |> Maybe.andThen identity
                                    )
                                |> Value.List ()
                                |> Ok
                    in
                    updateEditorState
                        (applyResult listValueResult
                            { editorState
                                | componentState = ListEditor itemType itemStates
                            }
                        )
            in
            row [] <|
                [ el labelStyle (text "list")
                , if List.isEmpty itemEditorStates then
                    el [] (plusButton (updateState [ defaultItemEditorState ]))

                  else
                    column [ spacing 5 ]
                        (itemEditorStates
                            |> List.indexedMap
                                (\index itemEditorState ->
                                    row []
                                        [ column [ height fill ]
                                            [ el
                                                [ alignTop, moveUp 10 ]
                                                (plusButton (updateState (itemEditorStates |> insert index defaultItemEditorState)))
                                            , if index == List.length itemEditorStates - 1 then
                                                el [ alignBottom, moveDown 9 ]
                                                    (closeButton (updateState (itemEditorStates |> insert (index + 1) defaultItemEditorState)))

                                              else
                                                none
                                            ]
                                        , view theme
                                            ir
                                            itemType
                                            (\newItemEditorState ->
                                                updateState (itemEditorStates |> set index newItemEditorState)
                                            )
                                            itemEditorState
                                        , closeButton (updateState (itemEditorStates |> remove index))
                                        ]
                                )
                        )
                ]

        GridEditor columnTypes cellEditorStates ->
            let
                set : Int -> Int -> a -> List (Array a) -> List (Array a)
                set rowIndex columnIndex item list =
                    List.concat
                        [ List.take rowIndex list
                        , list |> List.drop rowIndex |> List.take 1 |> List.map (Array.set columnIndex item)
                        , List.drop (rowIndex + 1) list
                        ]

                remove : Int -> List a -> List a
                remove index list =
                    List.concat
                        [ List.take index list
                        , List.drop (index + 1) list
                        ]

                emptyRowEditors : Array EditorState
                emptyRowEditors =
                    columnTypes
                        |> List.map
                            (\( _, columnType ) ->
                                initEditorState ir columnType Nothing
                            )
                        |> Array.fromList

                updateState : List (Array EditorState) -> msg
                updateState rowStates =
                    let
                        listValueResult : Result Error RawValue
                        listValueResult =
                            rowStates
                                |> List.map
                                    (\rowEditorStates ->
                                        columnTypes
                                            |> List.indexedMap
                                                (\columnIndex ( columnName, columnType ) ->
                                                    rowEditorStates
                                                        |> Array.get columnIndex
                                                        |> (\maybeValue ->
                                                                case maybeValue of
                                                                    Nothing ->
                                                                        Err <| "Missing row value"

                                                                    Just currentEditorState ->
                                                                        editorStateToRawValueResult currentEditorState
                                                                            |> Result.andThen
                                                                                (\maybeNextFieldValue ->
                                                                                    case maybeNextFieldValue of
                                                                                        Just nextFieldValue ->
                                                                                            Ok <| ( columnName, nextFieldValue )

                                                                                        Nothing ->
                                                                                            case columnType of
                                                                                                Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "maybe" ] ) _ ->
                                                                                                    Ok <| ( columnName, Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ) )

                                                                                                _ ->
                                                                                                    Err <| "Missing field value: " ++ Name.toCamelCase columnName
                                                                                )
                                                           )
                                                )
                                            |> ListOfResults.keepFirstError
                                            |> Result.map (Dict.fromList >> Value.Record ())
                                    )
                                |> ListOfResults.keepFirstError
                                |> Result.map (Value.List ())
                    in
                    updateEditorState
                        (applyResult listValueResult
                            { editorState
                                | componentState = GridEditor columnTypes rowStates
                            }
                        )
            in
            if List.isEmpty cellEditorStates then
                el [] (plusButton (updateState [ emptyRowEditors ]))

            else
                table
                    [ spacing 2
                    , paddingEach { top = 3, bottom = 10, left = 10, right = 10 }
                    , Background.color (rgb 0.8 0.8 0.8)
                    ]
                    { data = cellEditorStates |> List.indexedMap Tuple.pair
                    , columns =
                        columnTypes
                            |> List.indexedMap
                                (\columnIndex ( columnName, columnType ) ->
                                    { header =
                                        el [ width fill, height fill, paddingXY 10 5, Font.bold, Background.color (rgb 1 1 1) ]
                                            (el [ width fill, center ] (text (columnName |> Name.toHumanWords |> String.join " ")))
                                    , width = shrink
                                    , view =
                                        \( rowIndex, rowEditorStates ) ->
                                            let
                                                addButton : List (Array EditorState) -> Element msg
                                                addButton newStates =
                                                    if columnIndex == 0 then
                                                        el
                                                            [ moveUp 7
                                                            , moveLeft 7
                                                            ]
                                                            (plusButton (updateState newStates))

                                                    else
                                                        none

                                                removeButton : List (Array EditorState) -> Element msg
                                                removeButton newStates =
                                                    if columnIndex == List.length columnTypes - 1 then
                                                        el
                                                            [ moveDown 3
                                                            ]
                                                            (closeButton (updateState newStates))

                                                    else
                                                        none
                                            in
                                            el
                                                [ width fill
                                                , height fill
                                                , padding 1
                                                , Background.color (rgb 1 1 1)
                                                , inFront (addButton (emptyRowEditors :: cellEditorStates))
                                                , if rowIndex == List.length cellEditorStates - 1 then
                                                    below (addButton (cellEditorStates ++ [ emptyRowEditors ]))

                                                  else
                                                    below none
                                                , onRight (removeButton (cellEditorStates |> remove rowIndex))
                                                ]
                                                (view theme
                                                    ir
                                                    columnType
                                                    (\newItemEditorState ->
                                                        updateState (cellEditorStates |> set rowIndex columnIndex newItemEditorState)
                                                    )
                                                    (Array.get columnIndex rowEditorStates |> Maybe.withDefault (initEditorState ir columnType Nothing))
                                                )
                                    }
                                )
                    }

        DictEditor ( dictKeyType, dictValueType ) keyValueEditorStates ->
            let
                columnTypes =
                    [ ( [ "key" ], dictKeyType ), ( [ "value" ], dictValueType ) ]

                cellEditorStates =
                    keyValueEditorStates

                set : Int -> Int -> a -> List ( a, a ) -> List ( a, a )
                set rowIndex columnIndex item list =
                    List.concat
                        [ List.take rowIndex list
                        , list
                            |> List.drop rowIndex
                            |> List.take 1
                            |> List.map
                                (\( k, v ) ->
                                    if columnIndex == 0 then
                                        ( item, v )

                                    else
                                        ( k, item )
                                )
                        , List.drop (rowIndex + 1) list
                        ]

                remove : Int -> List a -> List a
                remove index list =
                    List.concat
                        [ List.take index list
                        , List.drop (index + 1) list
                        ]

                emptyRowEditors : ( EditorState, EditorState )
                emptyRowEditors =
                    ( initEditorState ir dictKeyType Nothing, initEditorState ir dictValueType Nothing )

                updateState : List ( EditorState, EditorState ) -> msg
                updateState rowStates =
                    let
                        listValueResult : Result Error RawValue
                        listValueResult =
                            rowStates
                                |> List.map
                                    (\( keyEditorState, valueEditorState ) ->
                                        Maybe.map2
                                            (\key value ->
                                                Value.Tuple () [ key, value ]
                                            )
                                            (editorStateToRawValueResult keyEditorState |> Result.toMaybe |> Maybe.andThen identity)
                                            (editorStateToRawValueResult valueEditorState |> Result.toMaybe |> Maybe.andThen identity)
                                    )
                                |> List.filterMap identity
                                |> Value.List ()
                                |> SDKDict.fromListValue ()
                                |> Ok
                    in
                    updateEditorState
                        (applyResult listValueResult
                            { editorState
                                | componentState = DictEditor ( dictKeyType, dictValueType ) rowStates
                            }
                        )
            in
            row [] <|
                [ el labelStyle (text "dictionary")
                , if List.isEmpty cellEditorStates then
                    el [] (plusButton (updateState [ emptyRowEditors ]))

                  else
                    table
                        [ spacing 2
                        , paddingEach { top = 3, bottom = 10, left = 10, right = 10 }
                        , Background.color (rgb 0.8 0.8 0.8)
                        ]
                        { data = cellEditorStates |> List.indexedMap Tuple.pair
                        , columns =
                            columnTypes
                                |> List.indexedMap
                                    (\columnIndex ( columnName, columnType ) ->
                                        { header =
                                            el [ width fill, height fill, paddingXY 10 5, Font.bold, Background.color (rgb 1 1 1) ]
                                                (el [ width fill, center ] (text (columnName |> Name.toHumanWords |> String.join " ")))
                                        , width = fill
                                        , view =
                                            \( rowIndex, rowEditorStates ) ->
                                                let
                                                    addButton : List ( EditorState, EditorState ) -> Element msg
                                                    addButton newStates =
                                                        if columnIndex == 0 then
                                                            el
                                                                [ moveUp 7
                                                                , moveLeft 7
                                                                ]
                                                                (plusButton (updateState newStates))

                                                        else
                                                            none

                                                    removeButton : List ( EditorState, EditorState ) -> Element msg
                                                    removeButton newStates =
                                                        if columnIndex == List.length columnTypes - 1 then
                                                            el
                                                                [ moveDown 3
                                                                ]
                                                                (closeButton (updateState newStates))

                                                        else
                                                            none
                                                in
                                                el
                                                    [ width fill
                                                    , height fill
                                                    , Background.color (rgb 1 1 1)
                                                    , inFront (addButton (emptyRowEditors :: cellEditorStates))
                                                    , if rowIndex == List.length cellEditorStates - 1 then
                                                        below (addButton (cellEditorStates ++ [ emptyRowEditors ]))

                                                      else
                                                        below none
                                                    , onRight (removeButton (cellEditorStates |> remove rowIndex))
                                                    ]
                                                    (view theme
                                                        ir
                                                        columnType
                                                        (\newItemEditorState ->
                                                            updateState (cellEditorStates |> set rowIndex columnIndex newItemEditorState)
                                                        )
                                                        (if columnIndex == 0 then
                                                            rowEditorStates |> Tuple.first

                                                         else
                                                            rowEditorStates |> Tuple.second
                                                        )
                                                    )
                                        }
                                    )
                        }
                ]

        GenericEditor currentText ->
            InputComponent.multiLine theme
                baseStyle
                { onChange =
                    \updatedText ->
                        let
                            valueResult tpe =
                                updatedText
                                    |> Frontend.mapValueToFile ir tpe
                                    |> Result.andThen
                                        (\sourceFileIR ->
                                            let
                                                packageName =
                                                    Path.fromString "My.Package"

                                                moduleName =
                                                    Path.fromString "A"

                                                localName =
                                                    Name.fromString "fooFunction"
                                            in
                                            case sourceFileIR |> Distribution.lookupValueDefinition ( packageName, moduleName, localName ) of
                                                Just valDef ->
                                                    Ok (valDef.body |> Value.toRawValue)

                                                Nothing ->
                                                    Err "Function name Not found"
                                        )
                        in
                        if updatedText == "" then
                            updateEditorState
                                (initEditorState ir valueType Nothing)

                        else
                            updateEditorState
                                (applyResult (valueResult (Distribution.resolveType valueType ir))
                                    { editorState
                                        | componentState = GenericEditor updatedText
                                    }
                                )
                , text = currentText
                , placeholder =
                    Just (placeholder [ center, paddingXY 0 1 ] (text "not set"))
                , label = Input.labelHidden ""
                , spellcheck = False
                }
                editorState.errorState

        LocalDateEditor state ->
            let
                localDateValue : String -> Value () ()
                localDateValue str =
                    fromISO () (Value.Literal () (StringLiteral str))
            in
            DatePicker.view theme
                { placeholder =
                    Just (placeholder [ center, paddingXY 0 1 ] (text "not set"))
                , label = el labelStyle (text "local date")
                , state = state
                , onStateChange =
                    \datePickerState ->
                        updateEditorState
                            (applyResult
                                (case datePickerState.date of
                                    Just date ->
                                        Ok <| localDateValue (toISOString date)

                                    Nothing ->
                                        Err "Invalid Date!"
                                )
                                { editorState
                                    | componentState = LocalDateEditor datePickerState
                                }
                            )
                }


viewCustomTypeEditor : Theme -> List (Element.Attribute msg) -> Distribution -> (EditorState -> msg) -> EditorState -> FQName -> Type.Constructors () -> CustomTypeEditorState -> Element msg
viewCustomTypeEditor theme labelStyle ir updateEditorState editorState (( packageName, moduleName, typeName ) as fqn) constructors customTypeEditorState =
    let
        viewConstructor : Element msg
        viewConstructor =
            Picklist.view theme
                { state = customTypeEditorState.constructorPicklistState
                , onStateChange =
                    \constructorPicklistState ->
                        case constructorPicklistState |> Picklist.getSelectedValue of
                            Nothing ->
                                updateEditorState
                                    { componentState =
                                        CustomTypeEditor fqn
                                            constructors
                                            { customTypeEditorState
                                                | constructorPicklistState = constructorPicklistState
                                                , argumentEditorStates = Dict.empty
                                            }
                                    , lastValidValue = Nothing
                                    , errorState = Nothing
                                    , defaultValueCheckbox = { show = False, checked = False }
                                    }

                            Just ( selectedConstructorName, selectedConstructorArgs ) ->
                                let
                                    argumentEditorStates : Dict Name ( Type (), EditorState )
                                    argumentEditorStates =
                                        selectedConstructorArgs
                                            |> List.map (\( name, tpe ) -> ( name, ( tpe, initEditorState ir tpe Nothing ) ))
                                            |> Dict.fromList
                                in
                                updateEditorState
                                    (applyResult (Ok (Value.Constructor () ( packageName, moduleName, selectedConstructorName )))
                                        { editorState
                                            | componentState =
                                                CustomTypeEditor fqn
                                                    constructors
                                                    { customTypeEditorState
                                                        | constructorPicklistState = constructorPicklistState
                                                        , argumentEditorStates = argumentEditorStates
                                                    }
                                        }
                                    )
                }
                (constructors
                    |> Dict.toList
                    |> List.map
                        (\(( ctorName, ctorArgs ) as ctor) ->
                            ( {tag  = ctorName |> Name.toTitleCase
                            , value = ctor
                            , displayElement = el [padding <| Theme.smallPadding theme, width fill] (Theme.ellipseText (ctorName |> Name.toHumanWordsTitle |> String.join " "))
                            } )
                        )
                )
                []

        viewArguments : List (Element msg)
        viewArguments =
            customTypeEditorState.argumentEditorStates
                |> Dict.toList
                |> List.map
                    (\( argumentName, ( argumentType, argumentEditorState ) ) ->
                        el
                            [ width fill
                            , height fill
                            , centerY
                            ]
                            (view theme
                                ir
                                argumentType
                                (\newArgumentEditorState ->
                                    let
                                        newArgumentEditorStates : Dict Name ( Type (), EditorState )
                                        newArgumentEditorStates =
                                            customTypeEditorState.argumentEditorStates
                                                |> Dict.insert argumentName ( argumentType, newArgumentEditorState )

                                        selectedConstructorResult : Result Error (Value () ())
                                        selectedConstructorResult =
                                            customTypeEditorState.constructorPicklistState
                                                |> Picklist.getSelectedValue
                                                |> Maybe.map
                                                    (\( ctorName, _ ) ->
                                                        Value.Constructor () ( packageName, moduleName, ctorName )
                                                    )
                                                |> Result.fromMaybe "No constructor selected"

                                        customResult : Result String RawValue
                                        customResult =
                                            newArgumentEditorStates
                                                |> Dict.toList
                                                |> List.foldl
                                                    (\( _, ( _, nextArgumentEditorState ) ) argumentsResultSoFar ->
                                                        argumentsResultSoFar
                                                            |> Result.andThen
                                                                (\argumentsSoFar ->
                                                                    editorStateToRawValueResult nextArgumentEditorState
                                                                        |> Result.map
                                                                            (\maybeNextArgumentValue ->
                                                                                case maybeNextArgumentValue of
                                                                                    Just nextArgumentValue ->
                                                                                        Apply () argumentsSoFar nextArgumentValue

                                                                                    Nothing ->
                                                                                        argumentsSoFar
                                                                            )
                                                                )
                                                    )
                                                    selectedConstructorResult
                                    in
                                    updateEditorState
                                        (applyResult customResult
                                            { editorState
                                                | componentState = CustomTypeEditor fqn constructors { customTypeEditorState | argumentEditorStates = newArgumentEditorStates }
                                            }
                                        )
                                )
                                argumentEditorState
                            )
                    )
    in
    row [ width fill, height fill, spacing 5 ]
        [ el labelStyle (text <| nameToText typeName)
        , viewConstructor
        , row
            [ width fill
            , spacing 5
            ]
            viewArguments
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


plusIcon : Element msg
plusIcon =
    html
        (Svg.svg
            [ Svg.Attributes.width "7px"
            , Svg.Attributes.height "7px"
            , Svg.Attributes.viewBox "0 0 200 200"
            ]
            [ Svg.polygon
                [ Svg.Attributes.points "80,0 120,0 120,80 200,80 200,120 120,120 120,200 80,200 80,120 0,120 0,80 80,80"
                , Svg.Attributes.style "fill: rgb(100,100,100)"
                ]
                []
            ]
        )


plusButton : msg -> Element msg
plusButton msg =
    el
        [ padding 2
        , Background.color (rgb 1 1 1)
        , Border.rounded 7
        , Border.color (rgb 0.8 0.8 0.8)
        , Border.width 2
        ]
        (Input.button []
            { onPress = Just msg
            , label = plusIcon
            }
        )


closeIcon : Element msg
closeIcon =
    html
        (Svg.svg
            [ Svg.Attributes.width "7px"
            , Svg.Attributes.height "7px"
            , Svg.Attributes.viewBox "0 0 200 200"
            ]
            [ Svg.polygon
                [ Svg.Attributes.points "80,0 120,0 120,80 200,80 200,120 120,120 120,200 80,200 80,120 0,120 0,80 80,80"
                , Svg.Attributes.style "fill: rgb(100,100,100)"
                , Svg.Attributes.transform "rotate(45,100,100)"
                ]
                []
            ]
        )


closeButton : msg -> Element msg
closeButton msg =
    el
        [ padding 2
        , Background.color (rgb 1 1 1)
        , Border.rounded 7
        , Border.color (rgb 0.8 0.8 0.8)
        , Border.width 2
        ]
        (Input.button []
            { onPress = Just msg
            , label = closeIcon
            }
        )
