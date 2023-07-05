module Morphir.Visual.Components.TypeBuilder exposing (NewType, State, init, view)

import Dict
import Element exposing (Element, above, column, el, fill, height, padding, paddingXY, row, scrollbars, spacing, text, width)
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
import Morphir.IR.Type as Type exposing (Definition(..), Type)
import Morphir.Visual.Common exposing (nameToTitleText)
import Morphir.Visual.Components.InputComponent as InputComponent
import Morphir.Visual.Components.Picklist as Picklist
import Morphir.Visual.Theme as Theme exposing (Theme)
import Ordering
import Element exposing (clipY)
import Element exposing (clipX)


type alias State =
    { typeName : String
    , typePickerState : Picklist.State (Type.Definition ())
    , modulePickerState : Picklist.State ModuleName
    , customTypeEditorState : CustomTypeEditorState
    }


type alias CustomTypeEditorState =
    { constructorNames : List Name
    , currentlyEditedConstructor : String
    , error : Maybe String
    }


type alias Config msg =
    { state : State
    , onStateChange : State -> msg
    , onTypeSave : NewType -> msg
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
    | TypePicklistChanged (Picklist.State (Type.Definition ()))
    | ModulePicklistChanged (Picklist.State ModuleName)
    | UpdateConstructorName String
    | SaveConstructorName
    | DeleteConstructorName Name


update : Msg -> State -> State
update typeBuildermsg state =
    let
        customTypeEditorState =
            state.customTypeEditorState
    in
    case typeBuildermsg of
        UpdateTypeName n ->
            { state | typeName = n }

        TypePicklistChanged newState ->
            { state | typePickerState = newState }

        UpdateConstructorName ctrName ->
            { state
                | customTypeEditorState =
                    { customTypeEditorState
                        | currentlyEditedConstructor = ctrName
                    }
            }

        ModulePicklistChanged newState ->
            { state | modulePickerState = newState }

        SaveConstructorName ->
            let
                ctrName =
                    Name.fromString customTypeEditorState.currentlyEditedConstructor
            in
            if not <| (List.member ctrName customTypeEditorState.constructorNames || String.isEmpty customTypeEditorState.currentlyEditedConstructor) then
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
                            | error = Just "This enum already has a member by this name"
                        }
                }

        DeleteConstructorName ctrToDelete ->
            { state
                | customTypeEditorState =
                    { customTypeEditorState
                        | constructorNames = List.Extra.remove ctrToDelete customTypeEditorState.constructorNames
                    }
            }


init : Maybe ModuleName -> State
init maybeModuleName =
    { typeName = ""
    , typePickerState = Picklist.init Nothing
    , modulePickerState = Picklist.init maybeModuleName
    , customTypeEditorState = initCustomTypeEditor
    }


initCustomTypeEditor : CustomTypeEditorState
initCustomTypeEditor =
    { constructorNames = []
    , currentlyEditedConstructor = ""
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
                    Nothing
                )

        createDropdownElement : a -> String -> String -> String -> { displayElement : Element msg, tag : String, value : a }
        createDropdownElement def tag displayName path =
            { displayElement =
                column [ padding (Theme.smallPadding theme), Element.clip, width fill ]
                    [ (displayName |> Theme.ellipseText) 
                    , el [Font.color theme.colors.mediumGray, Font.size (Theme.scaled 0 theme), paddingXY 0 2] (Theme.ellipseText path)
                    ]
            , tag = tag
            , value = def
            }

        modulePath mn =
            (List.map nameToTitleText mn |> List.reverse |> List.intersperse "> " |> List.foldl (++) "")

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
                                        (\( typeName, typedef ) ->
                                            createDropdownElement
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
                    (sdkTypes |> List.map (\( name, def ) -> createDropdownElement def name name "SDK"))
                    typeList
                )

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
                                    mn
                                    (List.map nameToTitleText mn |> List.reverse |> List.intersperse " " |> List.foldl (++) "")
                                    (mn |> List.reverse |> List.head |> Maybe.withDefault [] |> nameToTitleText )
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

        customTypeEditor : Element msg
        customTypeEditor =
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
                                { onPress = Just <| config.onStateChange (update (DeleteConstructorName ctrName) config.state)
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
                        [ onEnter <| config.onStateChange (update SaveConstructorName config.state) ]
                        { onChange = \s -> config.onStateChange (update (UpdateConstructorName s) config.state)
                        , text = config.state.customTypeEditorState.currentlyEditedConstructor
                        , placeholder = Just (Input.placeholder [] (text "Name..."))
                        , label = Input.labelHidden "Next consturctor name"
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
                        { onPress = Just <| config.onStateChange (update SaveConstructorName config.state)
                        , label = text " + "
                        }
            in
            column [ padding <| Theme.mediumPadding theme, spacing <| Theme.mediumSpacing theme ] [ constructorNames, row [ spacing (Theme.smallSpacing theme) ] [ ctrNameEditor, ctrSaveButton ] ]

        saveButton : Element msg
        saveButton =
            let
                saveTypeMessage : Maybe msg
                saveTypeMessage =
                    let
                        saveType : Type.Definition () -> NewType
                        saveType def =
                            { name = Name.fromString config.state.typeName
                            , definition =
                                case def of
                                    CustomTypeDefinition _ _ ->
                                        Type.customTypeDefinition [] (AccessControlled.public <| Dict.fromList (List.map (\n -> Tuple.pair n []) config.state.customTypeEditorState.constructorNames))

                                    _ ->
                                        def
                            , access = Public
                            , documentation = ""
                            , moduleName = config.state.modulePickerState.selectedValue |> Maybe.withDefault []
                            }
                    in
                    if config.state.typeName |> String.isEmpty then
                        Nothing

                    else
                        config.state.typePickerState.selectedValue |> Maybe.map (saveType >> config.onTypeSave)
            in
            Input.button
                [ padding 7
                , theme |> Theme.borderRounded
                , Background.color theme.colors.darkest
                , Font.color theme.colors.lightest
                , Font.bold
                , Font.size theme.fontSize
                ]
                { onPress = saveTypeMessage
                , label = row [ spacing (theme |> Theme.scaled -6) ] [ text "Save new term" ]
                }
    in
    column
        [ spacing (Theme.largeSpacing theme)
        , padding (Theme.largePadding theme)
        , height fill
        , width fill
        , scrollbars
        ]
        [ row
            [ spacing (Theme.mediumSpacing theme)
            ]
            [ typeNameInput
            , el [ Font.bold ] (text " is a kind of ")
            , typePicklist
            , el [ Font.bold ] (text " in ")
            , modulePicklist
            ]
        , case config.state.typePickerState.selectedValue of
            Just (CustomTypeDefinition _ _) ->
                column [ spacing (Theme.smallSpacing theme) ] [ el [ Font.bold ] (text " which can be one of: "), customTypeEditor ]

            _ ->
                Element.none
        , el [ paddingXY 0 (Theme.mediumPadding theme) ] saveButton
        ]


sdkTypes : List ( String, Type.Definition () )
sdkTypes =
    let
        customType : List ( String, Definition a )
        customType =
            [ ( "Enum", Type.customTypeDefinition [] (AccessControlled.public Dict.empty) ) ]
    in
    customType
        ++ ([ ( "Boolean", boolType () )
            , ( "Decimal", decimalType () )
            , ( "Integer", intType () )
            , ( "Floating Point Number", floatType () )
            , ( "Text", stringType () )
            ]
                |> List.map (Tuple.mapSecond (Type.typeAliasDefinition []))
           )


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
