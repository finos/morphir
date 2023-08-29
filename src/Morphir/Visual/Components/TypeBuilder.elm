module Morphir.Visual.Components.TypeBuilder exposing (NewType, State, init, view)

import Array
import Bootstrap.Form.Radio exposing (name)
import Dict
import Element exposing (Element, above, centerX, centerY, column, el, fill, fillPortion, height, padding, paddingEach, paddingXY, row, scrollbars, shrink, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html.Events
import Json.Decode as Decode
import List.Extra
import Morphir.IR.AccessControlled as AccessControlled exposing (Access(..))
import Morphir.IR.FQName as FQName
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.SDK.Basics exposing (boolType, floatType, intType)
import Morphir.IR.SDK.Decimal exposing (decimalType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type as Type exposing (Definition(..), Field, Type, record)
import Morphir.Visual.Common exposing (nameToTitleText)
import Morphir.Visual.Components.InputComponent as InputComponent
import Morphir.Visual.Components.Picklist as Picklist
import Morphir.Visual.Theme as Theme exposing (Theme)
import Ordering
import Morphir.IR.Path as Path


type alias State =
    { typeName : String
    , newModuleName : String
    , createNewModule : Bool
    , typePickerState : Picklist.State (Type.Definition ())
    , modulePickerState : Picklist.State ModuleName
    , customTypeEditorState : CustomTypeEditorState
    , recordTypeEditorState : RecordTypeEditorState
    , showSaveIR : Bool
    , documentation : String
    , typeNameError : Maybe String
    }


type alias CustomTypeEditorState =
    { constructorNames : List Name
    , currentlyEditedConstructor : String
    , error : Maybe String
    }


type alias RecordTypeEditorState =
    { recordFields : List (Field ())
    , currentlyEditedFieldName : String
    , currentlyEditedFieldType : Picklist.State (Type ())
    , currentlyEditedFieldOptional : Bool
    , error : Maybe String
    }


type alias Config msg =
    { state : State
    , onStateChange : State -> msg
    , onTypeAdd : NewType -> msg
    , onIRSave : msg
    }


type alias NewType =
    { moduleName : ModuleName
    , name : Name
    , definition : Type.Definition ()
    , access : Access
    , documentation : String
    }


type Msg
    = UpdateTypeName String
    | UpdateNewModuleName String
    | ToggleNewModule
    | TypePicklistChanged (Picklist.State (Type.Definition ()))
    | ModulePicklistChanged (Picklist.State ModuleName)
    | DocumentationChanged String
    | ConstructorEditor ConstructorEditorMsg
    | RecordEditor RecordEditorMsg


type ConstructorEditorMsg
    = UpdateConstructorName String
    | SaveConstructorName
    | DeleteConstructorName Name


type RecordEditorMsg
    = UpdateRecordFieldName String
    | RecordTypePicklistChanged (Picklist.State (Type ()))
    | DeleteField Name
    | SaveField (Maybe (Type ()))
    | ToggleFieldOptional Name Bool
    | ToggleNewFieldOptional Bool


update : Msg -> State -> State
update typeBuildermsg state =
    case typeBuildermsg of
        UpdateTypeName n ->
            { state
                | typeName = n
                , typeNameError =
                    if not <| isValidName [ n ] then
                        Just "This is not a valid name"

                    else
                        Nothing
            }

        UpdateNewModuleName n ->
            { state
                | newModuleName = n
            }

        TypePicklistChanged newState ->
            { state | typePickerState = newState }

        ModulePicklistChanged newState ->
            { state | modulePickerState = newState }

        ConstructorEditor msg ->
            let
                customTypeEditorState =
                    state.customTypeEditorState
            in
            case msg of
                UpdateConstructorName ctrName ->
                    { state
                        | customTypeEditorState =
                            { customTypeEditorState
                                | currentlyEditedConstructor = ctrName
                            }
                    }

                SaveConstructorName ->
                    let
                        ctrName : Name
                        ctrName =
                            Name.fromString customTypeEditorState.currentlyEditedConstructor
                    in
                    if
                        (not <|
                            List.member ctrName customTypeEditorState.constructorNames
                        )
                            && isValidName ctrName
                    then
                        { state
                            | customTypeEditorState =
                                { customTypeEditorState
                                    | constructorNames = (ctrName :: customTypeEditorState.constructorNames) |> List.sort
                                    , currentlyEditedConstructor = ""
                                    , error = Nothing
                                }
                        }

                    else
                        { state
                            | customTypeEditorState =
                                { customTypeEditorState
                                    | error = Just "This not a valid name"
                                }
                        }

                DeleteConstructorName ctrToDelete ->
                    { state
                        | customTypeEditorState =
                            { customTypeEditorState
                                | constructorNames = List.Extra.remove ctrToDelete customTypeEditorState.constructorNames
                            }
                    }

        RecordEditor msg ->
            let
                recordTypeEditorState =
                    state.recordTypeEditorState
            in
            case msg of
                UpdateRecordFieldName fieldName ->
                    { state
                        | recordTypeEditorState =
                            { recordTypeEditorState
                                | currentlyEditedFieldName = fieldName
                            }
                    }

                RecordTypePicklistChanged newState ->
                    { state
                        | recordTypeEditorState =
                            { recordTypeEditorState
                                | currentlyEditedFieldType = newState
                            }
                    }

                DeleteField fieldName ->
                    { state
                        | recordTypeEditorState =
                            { recordTypeEditorState
                                | recordFields = List.filter (\field -> not (field.name == fieldName)) recordTypeEditorState.recordFields
                            }
                    }

                SaveField maybeTpe ->
                    let
                        fieldName : Name
                        fieldName =
                            Name.fromString recordTypeEditorState.currentlyEditedFieldName

                        doesFieldExist : Name -> Bool
                        doesFieldExist fName =
                            recordTypeEditorState.recordFields |> List.any (\field -> field.name == fName)
                    in
                    case maybeTpe of
                        Just tpe ->
                            let
                                maybeOptionalType : Type ()
                                maybeOptionalType =
                                    if recordTypeEditorState.currentlyEditedFieldOptional then
                                        makeOptional tpe

                                    else
                                        tpe
                            in
                            if (not <| (doesFieldExist fieldName || String.isEmpty recordTypeEditorState.currentlyEditedFieldName)) && isValidName fieldName then
                                { state
                                    | recordTypeEditorState =
                                        { recordTypeEditorState
                                            | recordFields = ({ name = fieldName, tpe = maybeOptionalType } :: recordTypeEditorState.recordFields) |> List.sortWith (Ordering.byField .name)
                                            , currentlyEditedFieldName = ""
                                            , error = Nothing
                                            , currentlyEditedFieldType = Picklist.init Nothing
                                            , currentlyEditedFieldOptional = False
                                        }
                                }

                            else
                                { state
                                    | recordTypeEditorState =
                                        { recordTypeEditorState
                                            | error = Just "This is not a valid field name"
                                        }
                                }

                        Nothing ->
                            { state
                                | recordTypeEditorState =
                                    { recordTypeEditorState
                                        | error = Just "Please select a type"
                                    }
                            }

                ToggleFieldOptional fieldName optional ->
                    let
                        toggleOptional : Field () -> Field ()
                        toggleOptional field =
                            if field.name == fieldName then
                                if optional then
                                    { field | tpe = makeOptional field.tpe }

                                else
                                    { field | tpe = removeOptional field.tpe }

                            else
                                field
                    in
                    { state
                        | recordTypeEditorState =
                            { recordTypeEditorState
                                | recordFields = List.map toggleOptional recordTypeEditorState.recordFields
                            }
                    }

                ToggleNewFieldOptional optional ->
                    { state | recordTypeEditorState = { recordTypeEditorState | currentlyEditedFieldOptional = optional } }

        DocumentationChanged documentation ->
            { state | documentation = documentation }

        ToggleNewModule ->
            { state | createNewModule = not state.createNewModule }


init : Maybe ModuleName -> Bool -> State
init maybeModuleName showSaveIR =
    { typeName = ""
    , newModuleName = ""
    , createNewModule = False
    , typePickerState = Picklist.init Nothing
    , modulePickerState = Picklist.init maybeModuleName
    , customTypeEditorState = initCustomTypeEditor
    , recordTypeEditorState = initRecordTypeEditorState
    , showSaveIR = showSaveIR
    , documentation = ""
    , typeNameError = Nothing
    }


initCustomTypeEditor : CustomTypeEditorState
initCustomTypeEditor =
    { constructorNames = []
    , currentlyEditedConstructor = ""
    , error = Nothing
    }


initRecordTypeEditorState : RecordTypeEditorState
initRecordTypeEditorState =
    { recordFields = []
    , currentlyEditedFieldName = ""
    , currentlyEditedFieldType = Picklist.init Nothing
    , currentlyEditedFieldOptional = False
    , error = Nothing
    }


view : Theme -> Config msg -> PackageName -> Package.Definition () (Type ()) -> ModuleName -> Element msg
view theme config packageName packageDef moduleName =
    let
        typeNameInput : Element msg
        typeNameInput =
            el [ above (el [ padding (Theme.smallPadding theme), Font.color theme.colors.mediumGray ] (text "Name")), width fill ]
                (InputComponent.textInput
                    theme
                    []
                    { onChange = \s -> config.onStateChange (update (UpdateTypeName s) config.state)
                    , text = config.state.typeName
                    , placeholder = Just (Input.placeholder [] (text "Name your new term"))
                    , label = Input.labelHidden "Type's name"
                    }
                    config.state.typeNameError
                )

        typePicklist : Element msg
        typePicklist =
            let
                typeList : List { displayElement : Element msg, value : Definition (), tag : String }
                typeList =
                    packageDef.modules
                        |> Dict.toList
                        |> List.concatMap
                            (\( mn, accessControlledModuleDef ) ->
                                accessControlledModuleDef.value.types
                                    |> Dict.toList
                                    |> List.map
                                        (\( typeName, _ ) ->
                                            createDropdownElement
                                                theme
                                                (Type.typeAliasDefinition [] (Type.Reference () (FQName.fQName packageName moduleName typeName) []))
                                                (typeName |> nameToTitleText)
                                                (typeName |> nameToTitleText)
                                                (modulePath mn)
                                        )
                            )
                        |> List.sortWith (Ordering.byField .tag)
            in
            el [ above (el [ padding (Theme.smallPadding theme), Font.color theme.colors.mediumGray ] (text "Basis type")), width fill ]
                (Picklist.view theme
                    { state = config.state.typePickerState
                    , onStateChange = \pickListState -> config.onStateChange (update (TypePicklistChanged pickListState) config.state)
                    }
                    (builtInTypes |> List.map (\( name, def ) -> createDropdownElement theme def name name "SDK"))
                    typeList
                )

        newModuleNameInput : Element msg
        newModuleNameInput =
            el [ above (el [ padding (Theme.smallPadding theme), Font.color theme.colors.mediumGray ] (text "New Module's name")), width fill ]
                (InputComponent.textInput
                    theme
                    []
                    { onChange = \s -> config.onStateChange (update (UpdateNewModuleName s) config.state)
                    , text = config.state.newModuleName
                    , placeholder = Just (Input.placeholder [] (text "Name your new module"))
                    , label = Input.labelHidden "New Module's name"
                    }
                    config.state.typeNameError
                )

        toggleNewModuleButton : Element msg
        toggleNewModuleButton =
            Input.button
                [ padding 7
                , theme |> Theme.borderRounded
                , Background.color theme.colors.darkest
                , Font.color theme.colors.lightest
                , Font.bold
                , Font.size theme.fontSize
                ]
                { onPress = Just (config.onStateChange (update ToggleNewModule config.state))
                , label =
                    if config.state.createNewModule then
                        text "Pick Existing Module"

                    else
                        text "Create New Module"
                }

        getModuleName : ModuleName
        getModuleName = 
            if config.state.createNewModule then
                Path.fromString config.state.newModuleName
            else
                config.state.modulePickerState.selectedValue |> Maybe.withDefault []

        modulePicklist : Element msg
        modulePicklist =
            let
                getIntermediaryModules : ModuleName -> List ModuleName
                getIntermediaryModules mn =
                    List.foldl
                        (\m soFar ->
                            case m of
                                [] ->
                                    [ [ m ] ]

                                _ ->
                                    let
                                        lastSubPath =
                                            List.reverse (List.head soFar |> Maybe.withDefault [])

                                        newSubPath =
                                            m :: lastSubPath
                                    in
                                    List.reverse newSubPath :: soFar
                        )
                        []
                        mn

                moduleList : List { displayElement : Element msg, value : ModuleName, tag : String }
                moduleList =
                    (packageDef.modules
                        |> Dict.keys
                        |> List.concatMap getIntermediaryModules
                        |> List.Extra.unique
                        |> List.map
                            (\mn ->
                                createDropdownElement
                                    theme
                                    mn
                                    (List.map nameToTitleText mn |> List.reverse |> List.intersperse " " |> List.foldl (++) "")
                                    (mn |> List.reverse |> List.head |> Maybe.withDefault [] |> nameToTitleText)
                                    (modulePath mn)
                            )
                    )
                        |> List.sortWith (Ordering.byField .tag)
            in
            el [ above (el [ padding (Theme.smallPadding theme), Font.color theme.colors.mediumGray ] (text "Module")), width fill ]
                (Picklist.view theme
                    { state = config.state.modulePickerState
                    , onStateChange = \pickListState -> config.onStateChange (update (ModulePicklistChanged pickListState) config.state)
                    }
                    []
                    moduleList
                )

        saveButton : Element msg
        saveButton =
            Input.button
                [ padding 7
                , theme |> Theme.borderRounded
                , Background.color theme.colors.darkest
                , Font.color theme.colors.lightest
                , Font.bold
                , Font.size theme.fontSize
                ]
                { onPress = Just config.onIRSave
                , label = text "Save model"
                }

        documentationInput : Element msg
        documentationInput =
            InputComponent.multiLine theme
                [ width fill ]
                { onChange = \txt -> config.onStateChange (update (DocumentationChanged txt) config.state)
                , text = config.state.documentation
                , placeholder = Just (Input.placeholder [] (text "Add some documentation explaining the purpose of this term..."))
                , spellcheck = False
                , label = Input.labelAbove [] <| text "Documentation"
                }
                Nothing

        addTypeButton : Element msg
        addTypeButton =
            let
                addTypeMessage : Maybe msg
                addTypeMessage =
                    let
                        addType : Type.Definition () -> NewType
                        addType def =
                            { name = Name.fromString config.state.typeName
                            , definition =
                                case def of
                                    CustomTypeDefinition _ _ ->
                                        Type.customTypeDefinition [] (AccessControlled.public <| Dict.fromList (List.map (\n -> Tuple.pair n []) config.state.customTypeEditorState.constructorNames))

                                    TypeAliasDefinition _ (Type.Record _ _) ->
                                        Type.typeAliasDefinition [] (record () config.state.recordTypeEditorState.recordFields)

                                    _ ->
                                        def
                            , access = Public
                            , documentation = config.state.documentation
                            , moduleName = getModuleName
                            }
                    in
                    if (config.state.typeName |> String.isEmpty) || not ([ config.state.typeName ] |> isValidName) then
                        Nothing

                    else
                        config.state.typePickerState.selectedValue |> Maybe.map (addType >> config.onTypeAdd)
            in
            Input.button
                [ padding 7
                , theme |> Theme.borderRounded
                , Background.color theme.colors.darkest
                , Font.color theme.colors.lightest
                , Font.bold
                , Font.size theme.fontSize
                ]
                { onPress = addTypeMessage
                , label = text "Add new term"
                }
    in
    column
        [ spacing (Theme.largeSpacing theme)
        , padding (Theme.largePadding theme)
        , height fill
        , width fill
        ]
        [ row
            [ spacing (Theme.mediumSpacing theme)
            ]
            [ typeNameInput
            , el [ Font.bold ] (text " is a kind of ")
            , typePicklist
            , el [ Font.bold ] (text " in ")
            , column [ spacing (Theme.mediumPadding theme), width fill ]
                [ if config.state.createNewModule then
                    newModuleNameInput

                  else
                    modulePicklist
                , toggleNewModuleButton
                ]
            ]
        , case config.state.typePickerState.selectedValue of
            Just (CustomTypeDefinition _ _) ->
                column
                    [ spacing (Theme.smallSpacing theme) ]
                    [ el [ Font.bold ] (text " which can be one of: "), customTypeEditor theme config ]

            Just (TypeAliasDefinition _ (Type.Record _ _)) ->
                column
                    [ spacing (Theme.smallSpacing theme) ]
                    [ el [ Font.bold ] (text " with the following fields:  "), recordTypeEditor theme config packageName packageDef moduleName ]

            _ ->
                Element.none
        , documentationInput
        , row [ spacing <| Theme.largeSpacing theme ]
            (el [ paddingXY 0 (Theme.mediumPadding theme) ] addTypeButton
                :: (if config.state.showSaveIR then
                        [ el [ paddingXY 0 (Theme.mediumPadding theme) ] saveButton ]

                    else
                        []
                   )
            )
        ]


sdkTypes : List ( String, Type () )
sdkTypes =
    [ ( "Boolean", boolType () )
    , ( "Decimal", decimalType () )
    , ( "Integer", intType () )
    , ( "Floating Point Number", floatType () )
    , ( "Text", stringType () )
    ]


builtInTypes : List ( String, Type.Definition () )
builtInTypes =
    let
        customType : List ( String, Type.Definition () )
        customType =
            [ ( "Enum", Type.customTypeDefinition [] (AccessControlled.public Dict.empty) ) ]

        recordType : List ( String, Type.Definition () )
        recordType =
            [ ( "Record", Type.typeAliasDefinition [] (record () []) ) ]
    in
    customType ++ recordType ++ (sdkTypes |> List.map (Tuple.mapSecond (Type.typeAliasDefinition [])))


createDropdownElement : Theme -> a -> String -> String -> String -> { displayElement : Element msg, tag : String, value : a }
createDropdownElement theme def tag displayName path =
    { displayElement =
        column [ padding (Theme.smallPadding theme), Element.clip, width fill ]
            [ displayName |> Theme.ellipseText
            , el [ Font.color theme.colors.mediumGray, Font.size (Theme.scaled 0 theme), paddingXY 0 2 ] (Theme.ellipseText path)
            ]
    , tag = tag
    , value = def
    }


modulePath : ModuleName -> String
modulePath mn =
    List.map nameToTitleText mn |> List.reverse |> List.intersperse "> " |> List.foldl (++) ""


customTypeEditor : Theme -> Config msg -> Element msg
customTypeEditor theme config =
    let
        constructorNames : Element msg
        constructorNames =
            let
                deleteConstructorBtn : Name -> Element msg
                deleteConstructorBtn ctrName =
                    Input.button
                        [ theme |> Theme.borderRounded
                        , Background.color theme.colors.darkest
                        , Font.color theme.colors.lightest
                        , Font.bold
                        , Font.size theme.fontSize
                        , padding 2
                        ]
                        { onPress = Just <| config.onStateChange (update (ConstructorEditor <| DeleteConstructorName ctrName) config.state)
                        , label = text " x "
                        }
            in
            if List.isEmpty config.state.customTypeEditorState.constructorNames then
                Element.none

            else
                List.map
                    (\n -> row [ spacing (Theme.smallSpacing theme) ] [ el [ Font.bold, Theme.borderBottom 1, Border.color theme.colors.mediumGray ] (text <| nameToTitleText n), deleteConstructorBtn n ])
                    config.state.customTypeEditorState.constructorNames
                    ++ [ el [ Font.bold ] (text "or") ]
                    |> column [ spacing <| Theme.smallSpacing theme, padding <| Theme.smallPadding theme ]

        ctrNameEditor : Element msg
        ctrNameEditor =
            InputComponent.textInput
                theme
                [ onEnter <| config.onStateChange (update (ConstructorEditor SaveConstructorName) config.state) ]
                { onChange = \s -> config.onStateChange (update (ConstructorEditor <| UpdateConstructorName s) config.state)
                , text = config.state.customTypeEditorState.currentlyEditedConstructor
                , placeholder = Just (Input.placeholder [] (text "Name..."))
                , label = Input.labelHidden "Next constructor name"
                }
                config.state.customTypeEditorState.error

        ctrSaveButton : Element msg
        ctrSaveButton =
            Input.button
                [ theme |> Theme.borderRounded
                , Background.color theme.colors.darkest
                , Font.color theme.colors.lightest
                , Font.bold
                , Font.size theme.fontSize
                , padding (Theme.smallPadding theme)
                ]
                { onPress = Just <| config.onStateChange (update (ConstructorEditor SaveConstructorName) config.state)
                , label = text " + "
                }
    in
    column [ paddingXY (Theme.smallPadding theme) (Theme.mediumPadding theme), spacing <| Theme.mediumSpacing theme ] [ constructorNames, row [ spacing (Theme.smallSpacing theme) ] [ ctrNameEditor, ctrSaveButton ] ]


recordTypeEditor : Theme -> Config msg -> PackageName -> Package.Definition () (Type ()) -> ModuleName -> Element msg
recordTypeEditor theme config packageName packageDef moduleName =
    let
        elementList : List (Array.Array (Element msg))
        elementList =
            let
                deleteFieldBtn : Name -> Element msg
                deleteFieldBtn fieldName =
                    Input.button
                        [ theme |> Theme.borderRounded
                        , Background.color theme.colors.darkest
                        , Font.color theme.colors.lightest
                        , Font.bold
                        , Font.size theme.fontSize
                        , padding 2
                        , centerX
                        , centerY
                        , Font.center
                        ]
                        { onPress = Just <| config.onStateChange (update (RecordEditor <| DeleteField fieldName) config.state)
                        , label = el [ width shrink, centerX, centerY, Font.center ] <| text " x "
                        }

                leftColumn : Field () -> Element msg
                leftColumn field =
                    row [ Font.bold ] [ nameToTitleText field.name |> Theme.ellipseText ]

                rightColumn : Field () -> Element msg
                rightColumn field =
                    field.tpe |> Type.toString |> String.split "." |> List.Extra.last |> Maybe.withDefault "" |> text

                checkbox : Field () -> Element msg
                checkbox f =
                    isOptionalCheckbox
                        theme
                        (isOptional f.tpe)
                        (\b -> config.onStateChange (update (RecordEditor <| ToggleFieldOptional f.name b) config.state))

                fieldSaveButton : Element msg
                fieldSaveButton =
                    Input.button
                        [ padding 7
                        , theme |> Theme.borderRounded
                        , Background.color theme.colors.darkest
                        , Font.color theme.colors.lightest
                        , Font.bold
                        , Font.size theme.fontSize
                        ]
                        { onPress = Just <| config.onStateChange (update (RecordEditor <| SaveField config.state.recordTypeEditorState.currentlyEditedFieldType.selectedValue) config.state)
                        , label = text "Add field"
                        }

                newFieldOptionalCheckbox : Element msg
                newFieldOptionalCheckbox =
                    isOptionalCheckbox
                        theme
                        config.state.recordTypeEditorState.currentlyEditedFieldOptional
                        (\b -> config.onStateChange (update (RecordEditor <| ToggleNewFieldOptional b) config.state))

                fieldNameEditor : Element msg
                fieldNameEditor =
                    InputComponent.textInput
                        theme
                        [ width fill ]
                        { onChange = \s -> config.onStateChange (update (RecordEditor <| UpdateRecordFieldName s) config.state)
                        , text = config.state.recordTypeEditorState.currentlyEditedFieldName
                        , placeholder = Just (Input.placeholder [] (text "Name..."))
                        , label = Input.labelHidden "Next field name"
                        }
                        config.state.recordTypeEditorState.error

                typePicklist : Element msg
                typePicklist =
                    let
                        typeList : List { displayElement : Element msg, value : Type (), tag : String }
                        typeList =
                            packageDef.modules
                                |> Dict.toList
                                |> List.concatMap
                                    (\( mn, accessControlledModuleDef ) ->
                                        accessControlledModuleDef.value.types
                                            |> Dict.toList
                                            |> List.map
                                                (\( typeName, _ ) ->
                                                    createDropdownElement
                                                        theme
                                                        (Type.Reference () (FQName.fQName packageName moduleName typeName) [])
                                                        (typeName |> nameToTitleText)
                                                        (typeName |> nameToTitleText)
                                                        (modulePath mn)
                                                )
                                    )
                                |> List.sortWith (Ordering.byField .tag)
                    in
                    el [ width fill ]
                        (Picklist.view theme
                            { state = config.state.recordTypeEditorState.currentlyEditedFieldType
                            , onStateChange = \pickListState -> config.onStateChange (update (RecordEditor (RecordTypePicklistChanged pickListState)) config.state)
                            }
                            (sdkTypes |> List.map (\( name, def ) -> createDropdownElement theme def name name "SDK"))
                            typeList
                        )
            in
            List.map (\f -> Array.fromList [ checkbox f, leftColumn f, rightColumn f, deleteFieldBtn f.name ]) config.state.recordTypeEditorState.recordFields
                ++ [ Array.fromList [ newFieldOptionalCheckbox, fieldNameEditor, typePicklist, fieldSaveButton ] ]

        fieldTable : Element msg
        fieldTable =
            let
                header title =
                    el [ paddingXY 0 (Theme.largePadding theme), Font.color theme.colors.mediumGray ] (text title)

                getColumnElement : Int -> Array.Array (Element msg) -> Element msg
                getColumnElement index =
                    Array.get index >> Maybe.withDefault Element.none
            in
            Element.table
                [ width fill
                , paddingEach { bottom = Theme.smallPadding theme, top = 0, left = 0, right = 0 }
                , spacing <| Theme.mediumSpacing theme
                ]
                { columns =
                    [ { header = header "Optional?"
                      , width = fillPortion 2
                      , view =
                            \f ->
                                getColumnElement 0 f
                      }
                    , { header = header "Field Name"
                      , width = fillPortion 5
                      , view =
                            \f ->
                                getColumnElement 1 f
                      }
                    , { header = header "Field Type"
                      , width = fillPortion 5
                      , view =
                            \f ->
                                getColumnElement 2 f
                      }
                    , { header = Element.none
                      , width = shrink
                      , view =
                            \f ->
                                getColumnElement 3 f
                      }
                    ]
                , data = elementList
                }
    in
    column [ paddingXY (Theme.smallPadding theme) (Theme.mediumPadding theme), spacing <| Theme.mediumSpacing theme ] [ el [ Font.bold ] (text "{"), fieldTable, el [ Font.bold ] (text "}") ]


onEnter : msg -> Element.Attribute msg
onEnter msg =
    Element.htmlAttribute
        (Html.Events.on "keyup"
            (Decode.field "key" Decode.string
                |> Decode.andThen
                    (\key ->
                        if key == "Enter" then
                            Decode.succeed msg

                        else
                            Decode.fail "Not the enter key"
                    )
            )
        )


isOptional : Type () -> Bool
isOptional tpe =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "maybe" ] ) [ _ ] ->
            True

        _ ->
            False


makeOptional : Type () -> Type ()
makeOptional tpe =
    Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "maybe" ] ) [ tpe ]


removeOptional : Type () -> Type ()
removeOptional tpe =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "maybe" ] ) [ t ] ->
            t

        _ ->
            tpe


isOptionalCheckbox : Theme -> Bool -> (Bool -> msg) -> Element msg
isOptionalCheckbox theme isChecked message =
    InputComponent.checkBox theme
        []
        { onChange = \s -> message s
        , checked = isChecked
        , label = Input.labelHidden "is type optional?"
        }


isValidName : Name -> Bool
isValidName name =
    if List.isEmpty name then
        False

    else
        case name |> List.head of
            Nothing ->
                False

            Just str ->
                case str |> String.toList |> List.head of
                    Just char ->
                        Char.isAlpha char

                    Nothing ->
                        False
