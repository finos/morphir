module Morphir.Web.DevelopApp exposing (IRState(..), Model, Msg(..), Page(..), ServerState(..), httpMakeModel, init, main, routeParser, subscriptions, topUrlWithoutHome, update, view, viewBody, viewHeader)

import Array
import Browser
import Browser.Navigation as Nav
import Dict exposing (Dict)
import Element
    exposing
        ( Element
        , alignLeft
        , alignRight
        , alignTop
        , clipX
        , column
        , el
        , fill
        , fillPortion
        , height
        , html
        , image
        , layout
        , link
        , mouseOver
        , moveDown
        , none
        , padding
        , paddingEach
        , paddingXY
        , paragraph
        , pointer
        , px
        , rgb
        , rgba
        , rotate
        , row
        , scrollbarX
        , scrollbarY
        , scrollbars
        , spacing
        , text
        , width
        )
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input
import Html.Attributes exposing (name)
import Http exposing (Error(..), emptyBody, jsonBody)
import Markdown.Parser as Markdown
import Markdown.Renderer
import Morphir.Correctness.Codec exposing (decodeTestSuite, encodeTestSuite)
import Morphir.Correctness.Test exposing (TestSuite)
import Morphir.Dependency.DAG as DAG
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.Distribution.Codec as DistributionCodec
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.QName exposing (QName(..))
import Morphir.IR.Repo as Repo exposing (Repo)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Visual.Common exposing (nameToText, nameToTitleText)
import Morphir.Visual.Components.TreeLayout as TreeLayout
import Morphir.Visual.Config exposing (PopupScreenRecord)
import Morphir.Visual.Theme as Theme exposing (Theme)
import Morphir.Visual.XRayView as XRayView
import Morphir.Web.DevelopApp.Common exposing (ifThenElse, pathToDisplayString, pathToFullUrl, pathToUrl, urlFragmentToNodePath, viewAsCard)
import Morphir.Web.DevelopApp.FunctionPage as FunctionPage
import Morphir.Web.DevelopApp.ModulePage as ModulePage exposing (ViewType(..))
import Morphir.Web.Graph.DependencyGraph exposing (dependencyGraph)
import Morphir.Web.TryMorphir exposing (Model)
import Ordering
import Parser exposing (deadEndsToString)
import Set exposing (Set)
import Url exposing (Url)
import Url.Parser as UrlParser exposing (..)
import Url.Parser.Query as Query



-- MAIN


main : Program () Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }



-- MODEL


type alias Model =
    { key : Nav.Key
    , theme : Theme
    , irState : IRState
    , serverState : ServerState
    , testSuite : TestSuite
    , functionStates : Dict FQName FunctionPage.Model
    , collapsedModules : Set (TreeLayout.NodePath ModuleName)
    , simpleDefinitionDetailsModel : ModulePage.Model
    , showModules : Bool
    , homeState : HomeState
    , repo : Repo
    }


type alias HomeState =
    { selectedPackage : Maybe PackageName
    , selectedModule : Maybe ( TreeLayout.NodePath ModuleName, ModuleName )
    , selectedDefinition : Maybe Definition
    , filterState : FilterState
    }


type alias FilterState =
    { searchText : String
    , showValues : Bool
    , showTypes : Bool
    }


type alias ModelUpdate =
    Model -> Model


type Definition
    = Value ( ModuleName, Name )
    | Type ( ModuleName, Name )


type IRState
    = IRLoading
    | IRLoaded Distribution


type ServerState
    = ServerReady
    | ServerHttpError Http.Error


type Page
    = Home HomeState
    | Module ModulePage.Model
    | Function FQName
    | NotFound


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    let
        initModel =
            { key = key
            , theme = Theme.fromConfig Nothing
            , irState = IRLoading
            , serverState = ServerReady
            , testSuite = Dict.empty
            , functionStates = Dict.empty
            , collapsedModules = Set.empty
            , simpleDefinitionDetailsModel =
                { filter = Just ""
                , moduleName = []
                , viewType = ModulePage.InsightView
                , argState = Dict.empty
                , expandedValues = Dict.empty
                , popupVariables = PopupScreenRecord 0 Nothing
                , showSearchBar = False
                }
            , showModules = True
            , homeState =
                { selectedPackage = Nothing
                , selectedModule = Nothing
                , selectedDefinition = Nothing
                , filterState =
                    { searchText = ""
                    , showValues = True
                    , showTypes = True
                    }
                }
            , repo = Repo.empty []
            }
    in
    ( toRoute url initModel
    , Cmd.batch [ httpMakeModel ]
    )



-- UPDATE


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | HttpError Http.Error
    | ServerGetIRResponse Distribution
    | ServerGetTestsResponse TestSuite
    | InvalidArgValue FQName Name String
    | ExpandModule (TreeLayout.NodePath ModuleName)
    | CollapseModule (TreeLayout.NodePath ModuleName)
    | SearchDefinition String
    | ToggleValues Bool
    | ToggleTypes Bool
    | ToggleModulesMenu


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        getDistribution : Distribution
        getDistribution =
            case model.irState of
                IRLoaded distribution ->
                    distribution

                _ ->
                    Library [] Dict.empty Package.emptyDefinition

        getIR : IR
        getIR =
            IR.fromDistribution getDistribution
    in
    case msg |> Debug.log "msg" of
        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        UrlChanged url ->
            ( toRoute url model |> Debug.log "urlChanged", Cmd.none )

        HttpError httpError ->
            case model.irState of
                IRLoaded _ ->
                    ( model, Cmd.none )

                _ ->
                    ( { model | serverState = ServerHttpError httpError }
                    , Cmd.none
                    )

        ServerGetIRResponse distribution ->
            case Repo.fromDistribution distribution of
                Ok r ->
                    ( { model | irState = IRLoaded distribution, repo = r }
                    , httpTestModel (IR.fromDistribution distribution)
                    )

                Err _ ->
                    ( { model
                        | irState = IRLoaded distribution
                        , serverState =
                            ServerHttpError (Http.BadBody "Could not transform Distribution to Repo")
                      }
                    , httpTestModel (IR.fromDistribution distribution)
                    )

        ExpandModule nodePath ->
            ( { model | collapsedModules = model.collapsedModules |> Set.remove nodePath }, Cmd.none )

        CollapseModule nodePath ->
            ( { model | collapsedModules = model.collapsedModules |> Set.insert nodePath }, Cmd.none )

        ToggleModulesMenu ->
            ( { model
                | showModules = not model.showModules
              }
            , Cmd.none
            )

        SearchDefinition s ->
            let
                homeState : HomeState
                homeState =
                    model.homeState

                filterState : FilterState
                filterState =
                    homeState.filterState
            in
            ( { model | homeState = { homeState | filterState = { filterState | searchText = s } } }
            , Nav.replaceUrl model.key (filterStateToQueryParams { filterState | searchText = s })
            )

        ToggleValues v ->
            let
                filterState : FilterState
                filterState =
                    model.homeState.filterState
            in
            ( model
            , Nav.replaceUrl model.key (filterStateToQueryParams { filterState | showValues = v })
            )

        ToggleTypes t ->
            let
                filterState =
                    model.homeState.filterState
            in
            ( model
            , Nav.replaceUrl model.key (filterStateToQueryParams { filterState | showTypes = t })
            )

        ServerGetTestsResponse _ ->
            -- TODO: function test cases
            ( model, Cmd.none )

        InvalidArgValue _ _ _ ->
            -- TODO: todo implement
            ( model, Cmd.none )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- ROUTE


routeParser : Parser (ModelUpdate -> a) a
routeParser =
    UrlParser.oneOf [ topUrlWithoutHome, topUrlWithHome, packageUrl, moduleUrl, definitionUrl ]


updateHomeState : String -> String -> String -> FilterState -> ModelUpdate
updateHomeState pack mod def filterState =
    let
        toTypeOrValue m d =
            case String.uncons d of
                Just ( first, _ ) ->
                    if Char.isLower first then
                        Just (Value ( Path.fromString m, Name.fromString d ))

                    else
                        Just (Type ( Path.fromString m, Name.fromString d ))

                _ ->
                    Nothing

        updateModel : HomeState -> ModelUpdate
        updateModel newState model =
            { model | homeState = newState }
    in
    if pack == "" then
        updateModel
            { selectedPackage = Nothing
            , selectedModule = Nothing
            , selectedDefinition = Nothing
            , filterState = filterState
            }

    else if mod == "" then
        updateModel
            { selectedPackage = Just (Path.fromString pack)
            , selectedModule = Just ( urlFragmentToNodePath mod, [] )
            , selectedDefinition = Nothing
            , filterState = filterState
            }

    else
        updateModel
            { selectedPackage = Just (Path.fromString pack)
            , selectedModule = Just ( urlFragmentToNodePath mod, Path.fromString mod )
            , selectedDefinition = ifThenElse (def == "") Nothing (toTypeOrValue mod def)
            , filterState = filterState
            }


toRoute : Url -> Model -> Model
toRoute url =
    UrlParser.parse routeParser url
        |> Maybe.withDefault identity


topUrl : Parser (FilterState -> ModelUpdate) b -> Parser (b -> a) a
topUrl =
    UrlParser.map
        (\filter ->
            updateHomeState "" "" "" filter
        )


topUrlWithHome : Parser (ModelUpdate -> a) a
topUrlWithHome =
    topUrl <|
        UrlParser.s "home"
            <?> queryParams


topUrlWithoutHome : Parser (ModelUpdate -> a) a
topUrlWithoutHome =
    topUrl <|
        UrlParser.top
            <?> queryParams


packageUrl : Parser (ModelUpdate -> a) a
packageUrl =
    UrlParser.map
        (\pack filter ->
            updateHomeState pack "" "" filter
        )
    <|
        UrlParser.s "home"
            </> UrlParser.string
            <?> queryParams


moduleUrl : Parser (ModelUpdate -> a) a
moduleUrl =
    UrlParser.map
        (\pack mod filter ->
            updateHomeState pack mod "" filter
        )
    <|
        UrlParser.s "home"
            </> UrlParser.string
            </> UrlParser.string
            <?> queryParams


definitionUrl : Parser (ModelUpdate -> a) a
definitionUrl =
    UrlParser.map updateHomeState
        (UrlParser.s "home"
            </> UrlParser.string
            </> UrlParser.string
            </> UrlParser.string
            <?> queryParams
        )


queryParams : Query.Parser FilterState
queryParams =
    let
        trueOrFalse : Dict String Bool
        trueOrFalse =
            Dict.fromList [ ( "true", True ), ( "false", False ) ]

        search : Query.Parser String
        search =
            Query.string "search" |> Query.map (Maybe.withDefault "")

        showValues : Query.Parser Bool
        showValues =
            Query.enum "showValues" trueOrFalse |> Query.map (Maybe.withDefault True)

        showTypes : Query.Parser Bool
        showTypes =
            Query.enum "showTypes" trueOrFalse |> Query.map (Maybe.withDefault True)
    in
    Query.map3 FilterState search showValues showTypes


filterStateToQueryParams : FilterState -> String
filterStateToQueryParams filterState =
    let
        search : String
        search =
            ifThenElse (filterState.searchText == "") "" ("&search=" ++ filterState.searchText)

        filterValues : String
        filterValues =
            ifThenElse filterState.showValues "" "&showValues=false"

        filterTypes : String
        filterTypes =
            ifThenElse filterState.showTypes "" "&showTypes=false"
    in
    "?" ++ search ++ filterValues ++ filterTypes



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "Morphir - Home"
    , body =
        [ layout
            [ Font.family
                [ Font.external
                    { name = "Poppins"
                    , url = "https://fonts.googleapis.com/css2?family=Poppins:wght@300&display=swap"
                    }
                , Font.sansSerif
                ]
            , Font.size (model.theme |> Theme.scaled 2)
            , width fill
            , height fill
            , scrollbars
            ]
            (column
                [ width fill
                , height fill
                , scrollbars
                ]
                [ viewHeader model
                , case model.serverState of
                    ServerReady ->
                        none

                    ServerHttpError error ->
                        viewServerError error
                , el
                    [ width fill
                    , height fill
                    , scrollbars
                    ]
                    (viewBody model)
                ]
            )
        ]
    }


viewHeader : Model -> Element Msg
viewHeader model =
    column
        [ width fill
        , Background.color model.theme.colors.primaryHighlight
        ]
        [ row
            [ width fill
            ]
            [ row
                [ width fill
                ]
                [ el [ padding 6 ]
                    (image
                        [ height (px 40)
                        ]
                        { src = "/assets/2020_Morphir_Logo_Icon_WHT.svg"
                        , description = "Morphir Logo"
                        }
                    )
                , el
                    [ paddingXY 10 0
                    , Font.size (model.theme |> Theme.scaled 5)
                    ]
                    (text "Morphir Web")
                ]
            ]
        ]


viewServerError : Http.Error -> Element msg
viewServerError error =
    let
        message : String
        message =
            case error of
                Http.BadUrl url ->
                    "An invalid URL was provided: " ++ url

                Http.Timeout ->
                    "Request timed out"

                Http.NetworkError ->
                    "Network error"

                Http.BadStatus code ->
                    "Server returned an error: " ++ String.fromInt code

                Http.BadBody body ->
                    "Unexpected response body: " ++ body
    in
    el
        [ width fill
        , paddingXY 20 10
        , Background.color (rgb 1 0.5 0.5)
        , Font.color (rgb 1 1 1)
        ]
        (text message)


viewBody : Model -> Element Msg
viewBody model =
    case model.irState of
        IRLoading ->
            text "Loading the IR ..."

        IRLoaded (Library packageName _ packageDef) ->
            viewHome model packageName packageDef


viewHome : Model -> PackageName -> Package.Definition () (Type ()) -> Element Msg
viewHome model packageName packageDef =
    let
        gray =
            rgb 0.9 0.9 0.9

        scrollableListStyles : List (Element.Attribute msg)
        scrollableListStyles =
            [ width fill
            , height fill
            , Background.color model.theme.colors.lightest
            , Border.rounded 3
            , scrollbarY
            , paddingXY (model.theme |> Theme.scaled 3) (model.theme |> Theme.scaled -1)
            ]

        viewDefinition : Maybe Definition -> Element msg
        viewDefinition maybeSelectedDefinition =
            case maybeSelectedDefinition of
                Just selectedDefinition ->
                    case selectedDefinition of
                        Value ( moduleName, valueName ) ->
                            packageDef.modules
                                |> Dict.get moduleName
                                |> Maybe.andThen
                                    (\accessControlledModuleDef ->
                                        accessControlledModuleDef.value.values
                                            |> Dict.get valueName
                                            |> Maybe.map
                                                (\valueDef ->
                                                    viewValue model.theme moduleName valueName valueDef.value.value valueDef.value.doc
                                                )
                                    )
                                |> Maybe.withDefault none

                        Type ( moduleName, typeName ) ->
                            packageDef.modules
                                |> Dict.get moduleName
                                |> Maybe.andThen
                                    (\accessControlledModuleDef ->
                                        accessControlledModuleDef.value.types
                                            |> Dict.get typeName
                                            |> Maybe.map
                                                (\typeDef ->
                                                    viewType model.theme typeName typeDef.value.value typeDef.value.doc
                                                )
                                    )
                                |> Maybe.withDefault none

                Nothing ->
                    text "Please select a definition on the left!"

        moduleDefinitionsAsUiElements : ModuleName -> Module.Definition () (Type ()) -> List ( Definition, Element Msg )
        moduleDefinitionsAsUiElements moduleName moduleDef =
            let
                linkToDefinition : Name -> (Name -> String) -> String
                linkToDefinition name nameTransformation =
                    pathToFullUrl [ packageName, moduleName ] ++ "/" ++ nameTransformation name ++ filterStateToQueryParams model.homeState.filterState

                createUiElement : Element Msg -> Definition -> Name -> (Name -> String) -> Element Msg
                createUiElement icon definition name nameTransformation =
                    let
                        shouldColorBg =
                            case model.homeState.selectedDefinition of
                                Just defi ->
                                    definition == defi

                                Nothing ->
                                    False
                    in
                    viewAsLabel
                        model.theme
                        shouldColorBg
                        icon
                        (text (nameToText name))
                        (pathToDisplayString moduleName)
                        (linkToDefinition name nameTransformation)

                types : List ( Definition, Element Msg )
                types =
                    moduleDef.types
                        |> Dict.toList
                        |> List.map
                            (\( typeName, _ ) ->
                                ( Type ( moduleName, typeName )
                                , createUiElement (el [ Font.color (rgba 0 0.639 0.882 0.6) ] (text "ⓣ ")) (Type ( moduleName, typeName )) typeName Name.toTitleCase
                                )
                            )

                values : List ( Definition, Element Msg )
                values =
                    moduleDef.values
                        |> Dict.toList
                        |> List.map
                            (\( valueName, _ ) ->
                                ( Value ( moduleName, valueName )
                                , createUiElement (el [ Font.color (rgba 1 0.411 0 0.6) ] (text "ⓥ ")) (Value ( moduleName, valueName )) valueName Name.toCamelCase
                                )
                            )
            in
            ifThenElse model.homeState.filterState.showValues values [] ++ ifThenElse model.homeState.filterState.showTypes types []

        viewDefinitionLabels : Maybe ModuleName -> Element Msg
        viewDefinitionLabels maybeSelectedModuleName =
            let
                alphabeticalOrdering : List ( Definition, Element Msg ) -> List ( Definition, Element Msg )
                alphabeticalOrdering list =
                    let
                        byDefinitionName : ( Definition, Element Msg ) -> String
                        byDefinitionName ( definition, _ ) =
                            definition
                                |> definitionName
                                |> nameToText
                                |> String.toLower
                    in
                    List.sortWith
                        (Ordering.byField byDefinitionName)
                        list

                searchFilter : List ( Definition, Element Msg ) -> List ( Definition, Element Msg )
                searchFilter definitions =
                    let
                        searchTextContainsDefName : Name -> Bool
                        searchTextContainsDefName defName =
                            String.contains model.homeState.filterState.searchText (nameToText defName)
                    in
                    List.filter
                        (\( definition, _ ) ->
                            definition
                                |> definitionName
                                |> searchTextContainsDefName
                        )
                        definitions

                getElements : List ( Definition, Element Msg ) -> List (Element Msg)
                getElements definitionsAndElements =
                    let
                        displayList : List (Element Msg)
                        displayList =
                            List.map
                                (\( _, elem ) ->
                                    elem
                                )
                                definitionsAndElements
                    in
                    if List.isEmpty displayList then
                        if model.homeState.filterState.searchText == "" then
                            [ text "Please select a module on the left!" ]

                        else
                            [ text "No matching definition in this module." ]

                    else
                        displayList
            in
            packageDef.modules
                |> Dict.toList
                |> List.concatMap
                    (\( moduleName, accessControlledModuleDef ) ->
                        case maybeSelectedModuleName of
                            Just selectedModuleName ->
                                if selectedModuleName |> Path.isPrefixOf moduleName then
                                    moduleDefinitionsAsUiElements moduleName accessControlledModuleDef.value

                                else
                                    []

                            Nothing ->
                                []
                    )
                |> searchFilter
                |> alphabeticalOrdering
                |> getElements
                |> column [ height fill, width fill ]

        definitionFilter : Element Msg
        definitionFilter =
            Element.Input.search
                [ height fill
                , Font.size (model.theme |> Theme.scaled 2)
                , padding (model.theme |> Theme.scaled -2)
                , width (fillPortion 7)
                ]
                { onChange = SearchDefinition
                , text = model.homeState.filterState.searchText
                , placeholder = Just (Element.Input.placeholder [] (text "Search for a definition"))
                , label = Element.Input.labelHidden "Search"
                }

        valueCheckbox : Element Msg
        valueCheckbox =
            Element.Input.checkbox
                [ width (fillPortion 2) ]
                { onChange = ToggleValues
                , checked = model.homeState.filterState.showValues
                , icon = Element.Input.defaultCheckbox
                , label = Element.Input.labelLeft [] (text "values:")
                }

        typeCheckbox : Element Msg
        typeCheckbox =
            Element.Input.checkbox
                [ width (fillPortion 2) ]
                { onChange = ToggleTypes
                , checked = model.homeState.filterState.showTypes
                , icon = Element.Input.defaultCheckbox
                , label = Element.Input.labelLeft [] (text "types:")
                }

        toggleModulesMenu : Element Msg
        toggleModulesMenu =
            Element.Input.button
                [ padding 7
                , Background.color (rgba 0 0.639 0.882 0.6)
                , Border.rounded 3
                , Font.color model.theme.colors.lightest
                , Font.bold
                , Font.size (model.theme |> Theme.scaled 2)
                , mouseOver [ Background.color (rgb 0 0.639 0.882) ]
                ]
                { onPress = Just ToggleModulesMenu
                , label = row [ spacing (model.theme |> Theme.scaled -6) ] [ el [ width (px 20) ] <| text <| ifThenElse model.showModules "🗁" "🗀", text "Modules" ]
                }

        moduleTree : Element Msg
        moduleTree =
            el
                scrollableListStyles
                (TreeLayout.view TreeLayout.defaultTheme
                    { onCollapse = CollapseModule
                    , onExpand = ExpandModule
                    , collapsedPaths = model.collapsedModules
                    , selectedPaths =
                        model.homeState.selectedModule
                            |> Maybe.map (Tuple.first >> Set.singleton)
                            |> Maybe.withDefault Set.empty
                    }
                    (viewModuleNames model
                        packageName
                        []
                        (packageDef.modules |> Dict.keys)
                    )
                )

        pathToSelectedModule : String
        pathToSelectedModule =
            case model.homeState.selectedModule |> Maybe.map Tuple.second of
                Just moduleName ->
                    "> " ++ pathToDisplayString moduleName

                _ ->
                    ">"
    in
    row [ width fill, height fill, Background.color gray, spacing 10 ]
        [ column
            [ width (ifThenElse model.showModules (fillPortion 5) (fillPortion 3))
            , height fill
            , scrollbarX
            ]
            [ row
                [ height fill
                , width fill
                , spacing <| ifThenElse model.showModules 10 0
                , scrollbarX
                ]
                [ row
                    [ Background.color gray
                    , height fill
                    , width (ifThenElse model.showModules (fillPortion 2) (px 40))
                    , paddingXY 0 (model.theme |> Theme.scaled -3)
                    , scrollbarX
                    ]
                    [ el [ alignTop, rotate (degrees -90), width (px 40), moveDown 65, padding (model.theme |> Theme.scaled -6) ] <|
                        toggleModulesMenu
                    , ifThenElse model.showModules (el [ width fill, height fill, scrollbarX ] moduleTree) none
                    ]
                , column
                    [ Background.color gray
                    , height fill
                    , width (ifThenElse model.showModules (fillPortion 3) fill)
                    , spacing (model.theme |> Theme.scaled -4)
                    , clipX
                    ]
                    [ row
                        [ width fill
                        , spacing (model.theme |> Theme.scaled 1)
                        , paddingXY 0 (model.theme |> Theme.scaled -5)
                        , height <| fillPortion 1
                        ]
                        [ definitionFilter, row [ alignRight, spacing (model.theme |> Theme.scaled 1) ] [ valueCheckbox, typeCheckbox ] ]
                    , row [ width fill, height <| fillPortion 1, Font.bold, paddingXY 5 0 ] [ Theme.ellipseText pathToSelectedModule ]
                    , row [ width fill, height <| fillPortion 28 ]
                        [ el
                            scrollableListStyles
                            (viewDefinitionLabels (model.homeState.selectedModule |> Maybe.map Tuple.second))
                        ]
                    ]
                ]
            ]
        , column
            [ height fill
            , width (ifThenElse model.showModules (fillPortion 6) (fillPortion 7))
            , Background.color model.theme.colors.lightest
            , scrollbars
            ]
            [ ifThenElse (model.homeState.selectedDefinition == Nothing)
                (dependencyGraph model.homeState.selectedModule model.repo)
                (column
                    [ height (fillPortion 2), paddingEach { bottom = 3, top = model.theme |> Theme.scaled 1, left = model.theme |> Theme.scaled 1, right = 0 }, scrollbarX, width fill ]
                    [ viewDefinition model.homeState.selectedDefinition
                    , el [ height fill, width fill, scrollbars ]
                        (viewDefinitionDetails model.irState model.homeState.selectedDefinition)
                    ]
                )
            ]
        ]


viewType : Theme -> Name -> Type.Definition () -> String -> Element msg
viewType theme typeName typeDef docs =
    case typeDef of
        Type.TypeAliasDefinition _ (Type.Record _ fields) ->
            let
                fieldNames : { a | name : Name } -> Element msg
                fieldNames =
                    \field ->
                        el
                            (Theme.boldLabelStyles theme)
                            (text (nameToText field.name))

                fieldTypes : { a | tpe : Type () } -> Element msg
                fieldTypes =
                    \field ->
                        el
                            (Theme.labelStyles theme)
                            (XRayView.viewType pathToUrl field.tpe)

                viewFields : Element msg
                viewFields =
                    Theme.twoColumnTableView
                        fields
                        fieldNames
                        fieldTypes
            in
            viewAsCard theme
                (typeName |> nameToTitleText |> text)
                "record"
                theme.colors.backgroundColor
                docs
                viewFields

        Type.TypeAliasDefinition _ body ->
            viewAsCard theme
                (typeName |> nameToTitleText |> text)
                "is a"
                theme.colors.backgroundColor
                docs
                (el
                    [ paddingXY 10 5
                    ]
                    (XRayView.viewType pathToUrl body)
                )

        Type.CustomTypeDefinition _ accessControlledConstructors ->
            let
                isNewType : Maybe (Type ())
                isNewType =
                    case accessControlledConstructors.value |> Dict.toList of
                        [ ( ctorName, [ ( _, baseType ) ] ) ] ->
                            if ctorName == typeName then
                                Just baseType

                            else
                                Nothing

                        _ ->
                            Nothing

                isEnum : Bool
                isEnum =
                    accessControlledConstructors.value
                        |> Dict.values
                        |> List.all List.isEmpty

                viewConstructors : Element msg
                viewConstructors =
                    if isEnum then
                        accessControlledConstructors.value
                            |> Dict.toList
                            |> List.map
                                (\( ctorName, _ ) ->
                                    el
                                        (Theme.boldLabelStyles theme)
                                        (text (nameToTitleText ctorName))
                                )
                            |> column [ width fill ]

                    else
                        case isNewType of
                            Just baseType ->
                                el [ padding (theme |> Theme.scaled -2) ] (XRayView.viewType pathToUrl baseType)

                            Nothing ->
                                let
                                    constructorNames =
                                        \( ctorName, _ ) ->
                                            el
                                                (Theme.boldLabelStyles theme)
                                                (text (nameToTitleText ctorName))

                                    constructorArgs =
                                        \( _, ctorArgs ) ->
                                            el
                                                (Theme.labelStyles theme)
                                                (ctorArgs
                                                    |> List.map (Tuple.second >> XRayView.viewType pathToUrl)
                                                    |> row [ spacing 5 ]
                                                )
                                in
                                Theme.twoColumnTableView
                                    (Dict.toList accessControlledConstructors.value)
                                    constructorNames
                                    constructorArgs
            in
            viewAsCard theme
                (typeName |> nameToTitleText |> text)
                (case isNewType of
                    Just _ ->
                        "wrapper"

                    Nothing ->
                        if isEnum then
                            "enum"

                        else
                            "one of"
                )
                Theme.defaultColors.backgroundColor
                docs
                viewConstructors


viewValue : Theme -> ModuleName -> Name -> Value.Definition () (Type ()) -> String -> Element msg
viewValue theme moduleName valueName valueDef docs =
    let
        cardTitle : Element msg
        cardTitle =
            link [ pointer ]
                { url =
                    "/module/" ++ (moduleName |> List.map Name.toTitleCase |> String.join ".") ++ "?filter=" ++ nameToText valueName
                , label =
                    text (nameToText valueName)
                }

        isData : Bool
        isData =
            List.isEmpty valueDef.inputTypes

        backgroundColor : Element.Color
        backgroundColor =
            if isData then
                rgb 0.8 0.9 0.9

            else
                rgb 0.8 0.8 0.9
    in
    viewAsCard theme
        cardTitle
        (if isData then
            "value"

         else
            "calculation"
        )
        backgroundColor
        (ifThenElse (docs == "") "Placeholder Documentation. Docs would go here, if whe had them. This would be the place for documentation. This documentation might be long. It might also include **markdown**. `monospaced code`" docs)
        none


viewAsCard : Theme -> Element msg -> String -> Element.Color -> String -> Element msg -> Element msg
viewAsCard theme header class backgroundColor docs content =
    let
        white =
            rgb 1 1 1

        cont =
            el
                [ alignTop
                , height fill
                , width fill
                ]
                content
    in
    column
        [ padding (theme |> Theme.scaled 3)
        , spacing (theme |> Theme.scaled 3)
        ]
        [ row
            [ width fill
            , paddingXY (theme |> Theme.scaled -2) (theme |> Theme.scaled -6)
            , spacing (theme |> Theme.scaled 2)
            , Font.size (theme |> Theme.scaled 3)
            ]
            [ el [ Font.bold ] header
            , el [ alignLeft, Font.color theme.colors.secondaryInformation ] (text class)
            ]
        , el
            [ Background.color white
            , Border.rounded 3
            , width fill
            , height fill
            ]
            (if docs == "" then
                cont

             else
                column [ height fill, width fill ]
                    [ el
                        [ padding (theme |> Theme.scaled -2)
                        , Border.widthEach { bottom = 3, top = 0, left = 0, right = 0 }
                        , Border.color backgroundColor
                        , height fill
                        , width fill
                        ]
                        (let
                            deadEndsToString deadEnds =
                                deadEnds
                                    |> List.map Markdown.deadEndToString
                                    |> String.join "\n"
                         in
                         case
                            docs
                                |> Markdown.parse
                                |> Result.mapError deadEndsToString
                                |> Result.andThen (\ast -> Markdown.Renderer.render Markdown.Renderer.defaultHtmlRenderer ast)
                         of
                            Ok rendered ->
                                rendered |> List.map html |> paragraph []

                            Err errors ->
                                text errors
                        )
                    , cont
                    ]
            )
        ]


viewAsLabel : Theme -> Bool -> Element msg -> Element msg -> String -> String -> Element msg
viewAsLabel theme shouldColorBg icon header class url =
    let
        elem =
            row
                ([ width fill
                 , Font.size (theme |> Theme.scaled 2)
                 ]
                    ++ ifThenElse shouldColorBg [ Background.color theme.colors.selectionColor ] []
                )
                [ icon
                , el
                    [ Font.bold
                    , paddingXY (theme |> Theme.scaled -10) (theme |> Theme.scaled -3)
                    ]
                    header
                , el
                    ([ alignRight
                     , Font.color theme.colors.secondaryInformation
                     , paddingXY (theme |> Theme.scaled -10) (theme |> Theme.scaled -3)
                     ]
                        ++ ifThenElse shouldColorBg [ Background.color theme.colors.selectionColor ] []
                    )
                  <|
                    text class
                ]
    in
    link
        [ Border.color theme.colors.lightest
        , Border.widthEach
            { bottom = 1
            , left = 0
            , top = 0
            , right = 0
            }
        , mouseOver [ Border.color theme.colors.darkest ]
        , pointer
        , width fill
        ]
        { label = elem, url = url }



-- HTTP


httpMakeModel : Cmd Msg
httpMakeModel =
    Http.get
        { url = "/server/morphir-ir.json"
        , expect =
            Http.expectJson
                (\response ->
                    case response of
                        Err httpError ->
                            HttpError httpError

                        Ok result ->
                            ServerGetIRResponse result
                )
                DistributionCodec.decodeVersionedDistribution
        }


httpTestModel : IR -> Cmd Msg
httpTestModel ir =
    Http.get
        { url = "/server/morphir-tests.json"
        , expect =
            Http.expectJson
                (\response ->
                    case response of
                        Err httpError ->
                            HttpError httpError

                        Ok result ->
                            ServerGetTestsResponse result
                )
                (decodeTestSuite ir)
        }


httpSaveTestSuite : IR -> TestSuite -> Cmd Msg
httpSaveTestSuite ir testSuite =
    let
        encodedTestSuite =
            case encodeTestSuite ir testSuite of
                Ok encodedValue ->
                    jsonBody encodedValue

                Err _ ->
                    emptyBody
    in
    Http.post
        { url = "/server/morphir-tests.json"
        , body = encodedTestSuite
        , expect =
            Http.expectJson
                (\response ->
                    case response of
                        Err httpError ->
                            HttpError httpError

                        Ok result ->
                            ServerGetTestsResponse result
                )
                (decodeTestSuite ir)
        }


viewModuleNames : Model -> PackageName -> ModuleName -> List ModuleName -> TreeLayout.Node ModuleName Msg
viewModuleNames model packageName parentModule allModuleNames =
    let
        currentModuleName : Maybe Name
        currentModuleName =
            parentModule
                |> List.reverse
                |> List.head

        childModuleNames : List Name
        childModuleNames =
            allModuleNames
                |> List.filterMap
                    (\moduleName ->
                        if parentModule |> Path.isPrefixOf moduleName then
                            moduleName |> List.drop (List.length parentModule) |> List.head

                        else
                            Nothing
                    )
                |> Set.fromList
                |> Set.toList
    in
    TreeLayout.Node
        (\_ ->
            case currentModuleName of
                Just name ->
                    link [ pointer ] { label = text (name |> nameToTitleText), url = pathToFullUrl [ packageName, parentModule ] ++ filterStateToQueryParams model.homeState.filterState }

                Nothing ->
                    link [ pointer ] { label = text (pathToUrl packageName), url = pathToFullUrl [ packageName ] ++ filterStateToQueryParams model.homeState.filterState }
        )
        Array.empty
        (childModuleNames
            |> List.map
                (\name ->
                    let
                        moduleName =
                            parentModule ++ [ name ]
                    in
                    ( moduleName, viewModuleNames model packageName moduleName allModuleNames )
                )
            |> Dict.fromList
        )


definitionName : Definition -> Name
definitionName definition =
    case definition of
        Value ( _, valueName ) ->
            valueName

        Type ( _, typeName ) ->
            typeName


viewDefinitionDetails : IRState -> Maybe Definition -> Element Msg
viewDefinitionDetails irState maybeSelectedDefinition =
    case irState of
        IRLoading ->
            none

        IRLoaded (Library _ _ packageDef) ->
            case maybeSelectedDefinition of
                Just selectedDefinition ->
                    case selectedDefinition of
                        Value ( moduleName, valueName ) ->
                            packageDef.modules
                                |> Dict.get moduleName
                                |> Maybe.andThen
                                    (\accessControlledModuleDef ->
                                        accessControlledModuleDef.value.values
                                            |> Dict.get valueName
                                            |> Maybe.map
                                                (\_ ->
                                                    case packageDef.modules |> Dict.get moduleName of
                                                        Just acmoduledef ->
                                                            acmoduledef.value.values
                                                                |> Dict.get valueName
                                                                |> Maybe.andThen
                                                                    (\accessControlledValueDef ->
                                                                        Just <| XRayView.viewValueDefinition (XRayView.viewType <| pathToUrl) accessControlledValueDef.value.value
                                                                    )
                                                                |> Maybe.withDefault none

                                                        Nothing ->
                                                            none
                                                )
                                    )
                                |> Maybe.withDefault none

                        Type _ ->
                            none

                Nothing ->
                    none
