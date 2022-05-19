module Morphir.Web.DevelopApp exposing (IRState(..), Model, Msg(..), ServerState(..), httpMakeModel, init, main, routeParser, subscriptions, update, view, viewBody, viewHeader)

import Array exposing (Array)
import Browser
import Browser.Navigation as Nav
import Dict exposing (Dict)
import Element
    exposing
        ( Element
        , alignLeft
        , alignRight
        , alignTop
        , centerX
        , centerY
        , clipX
        , clipY
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
        , scrollbars
        , spacing
        , spacingXY
        , text
        , width
        )
import Element.Background as Background
import Element.Border as Border
import Element.Events exposing (onClick)
import Element.Font as Font
import Element.Input
import Element.Keyed
import Html.Attributes exposing (name)
import Http exposing (Error(..), emptyBody, jsonBody)
import Markdown.Parser as Markdown
import Markdown.Renderer
import Morphir.Correctness.Codec exposing (decodeTestSuite, encodeTestSuite)
import Morphir.Correctness.Test exposing (TestCase, TestSuite)
import Morphir.Elm.Backend.Dapr.StatefulApp exposing (test)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.Distribution.Codec as DistributionCodec
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.QName exposing (QName(..))
import Morphir.IR.Repo as Repo exposing (Repo)
import Morphir.IR.SDK as SDK
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, Value)
import Morphir.Type.Infer as Infer
import Morphir.Value.Error exposing (Error(..))
import Morphir.Value.Interpreter exposing (evaluateFunctionValue)
import Morphir.Visual.Common exposing (nameToText, nameToTitleText)
import Morphir.Visual.Components.FieldList as FieldList
import Morphir.Visual.Components.TreeLayout as TreeLayout
import Morphir.Visual.Config exposing (PopupScreenRecord)
import Morphir.Visual.EnrichedValue exposing (fromRawValue)
import Morphir.Visual.Theme as Theme exposing (Theme)
import Morphir.Visual.ValueEditor as ValueEditor
import Morphir.Visual.ViewValue as ViewValue
import Morphir.Visual.XRayView as XRayView
import Morphir.Web.DevelopApp.Common as Common exposing (ifThenElse, pathToDisplayString, pathToFullUrl, pathToUrl, urlFragmentToNodePath, viewAsCard)
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
        , onUrlChange = Navigate << UrlChanged
        , onUrlRequest = Navigate << LinkClicked
        }



-- MODEL


type alias Model =
    { key : Nav.Key
    , theme : Theme
    , irState : IRState
    , serverState : ServerState
    , testSuite : Dict FQName (Array TestCase)
    , collapsedModules : Set (TreeLayout.NodePath ModuleName)
    , showModules : Bool
    , showDefinitions : Bool
    , homeState : HomeState
    , repo : Repo
    , insightViewState : Morphir.Visual.Config.VisualState
    , definitionDisplayType : DisplayType
    , argStates : InsightArgumentState
    , expandedValues : Dict ( FQName, Name ) (Value.Definition () (Type ()))
    }


type alias InsightArgumentState =
    Dict Name ValueEditor.EditorState


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
    , moduleClicked : String
    }


type DisplayType
    = XRayView
    | InsightView


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


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    let
        initModel =
            { key = key
            , theme = Theme.fromConfig Nothing
            , irState = IRLoading
            , serverState = ServerReady
            , testSuite = Dict.empty
            , collapsedModules = Set.empty
            , showModules = True
            , showDefinitions = True
            , homeState =
                { selectedPackage = Nothing
                , selectedModule = Nothing
                , selectedDefinition = Nothing
                , filterState =
                    { searchText = ""
                    , showValues = True
                    , showTypes = True
                    , moduleClicked = ""
                    }
                }
            , repo = Repo.empty []
            , insightViewState = emptyVisualState
            , definitionDisplayType = XRayView
            , argStates = Dict.empty
            , expandedValues = Dict.empty
            }
    in
    ( toRoute url initModel
    , Cmd.batch [ httpMakeModel ]
    )


emptyVisualState : Morphir.Visual.Config.VisualState
emptyVisualState =
    { theme = Theme.fromConfig Nothing
    , expandedFunctions = Dict.empty
    , variables = Dict.empty
    , highlightState = Nothing
    , popupVariables =
        { variableIndex = 0
        , variableValue = Nothing
        }
    }



-- UPDATE


type Msg
    = Navigate NavigationMsg
    | HttpError Http.Error
    | ServerGetIRResponse Distribution
    | ServerGetTestsResponse TestSuite
    | Filter FilterMsg
    | UI UIMsg
    | Insight InsightMsg
    | Testing TestingMsg


type TestingMsg
    = DescriptionUpdated Int String
    | DeleteTestCase Int
    | SaveTestSuite FQName TestCase
    | LoadTestCase (List ( Name, Type () )) (List RawValue)


type NavigationMsg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url


type UIMsg
    = ToggleModulesMenu
    | ToggleDefinitionsMenu
    | ExpandModule (TreeLayout.NodePath ModuleName)
    | CollapseModule (TreeLayout.NodePath ModuleName)


type FilterMsg
    = SearchDefinition String
    | ToggleValues Bool
    | ToggleTypes Bool
    | ModuleClicked String


type InsightMsg
    = ExpandReference FQName Bool
    | ExpandVariable Int (Maybe RawValue)
    | ShrinkVariable Int
    | SwitchDisplayType
    | ArgValueUpdated Name ValueEditor.EditorState


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

        fromStoredTestSuite : Dict comparable (List a) -> Dict comparable (Array a)
        fromStoredTestSuite testSuite =
            Dict.fromList (List.map (\( k, v ) -> ( k, Array.fromList v )) (Dict.toList testSuite))

        toStoredTestSuite : Dict comparable (Array a) -> Dict comparable (List a)
        toStoredTestSuite testSuite =
            Dict.fromList (List.map (\( k, v ) -> ( k, Array.toList v )) (Dict.toList testSuite))
    in
    case msg of
        Navigate navigationMsg ->
            case navigationMsg of
                LinkClicked urlRequest ->
                    case urlRequest of
                        Browser.Internal url ->
                            ( model, Nav.pushUrl model.key (Url.toString url) )

                        Browser.External href ->
                            ( model, Nav.load href )

                UrlChanged url ->
                    ( toRoute url model, Cmd.none )

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

        UI uiMsg ->
            case uiMsg of
                ExpandModule nodePath ->
                    ( { model | collapsedModules = model.collapsedModules |> Set.remove nodePath }, Cmd.none )

                CollapseModule nodePath ->
                    ( { model | collapsedModules = model.collapsedModules |> Set.insert nodePath }, Cmd.none )

                ToggleModulesMenu ->
                    ( { model
                        | showModules = not model.showModules
                        , showDefinitions = ifThenElse (not model.showModules) True model.showDefinitions
                      }
                    , Cmd.none
                    )

                ToggleDefinitionsMenu ->
                    ( { model
                        | showDefinitions = not model.showDefinitions
                        , showModules = ifThenElse (not model.showDefinitions) model.showDefinitions False
                      }
                    , Cmd.none
                    )

        ServerGetTestsResponse testSuite ->
            ( { model | testSuite = fromStoredTestSuite testSuite }, Cmd.none )

        Insight insightMsg ->
             let
                insightViewState : Morphir.Visual.Config.VisualState
                insightViewState =
                    model.insightViewState
            in
            case insightMsg of
                ExpandReference (( _, moduleName, localName ) as fQName) isFunctionPresent ->
                    if model.expandedValues |> Dict.member ( fQName, localName ) then
                        if isFunctionPresent then
                            ( { model | expandedValues = model.expandedValues |> Dict.remove ( fQName, localName ) }, Cmd.none )

                        else
                            ( model, Cmd.none )

                    else
                        ( { model
                            | expandedValues =
                                Distribution.lookupValueDefinition (QName moduleName localName)
                                    getDistribution
                                    |> Maybe.map (\valueDef -> model.expandedValues |> Dict.insert ( fQName, localName ) valueDef)
                                    |> Maybe.withDefault model.expandedValues
                          }
                        , Cmd.none
                        )

                ExpandVariable varIndex maybeRawValue ->
                    ( { model | insightViewState = { insightViewState | popupVariables = PopupScreenRecord varIndex maybeRawValue } }, Cmd.none )

                ShrinkVariable varIndex ->
                    ( { model | insightViewState = { insightViewState | popupVariables = PopupScreenRecord varIndex Nothing } }, Cmd.none )

                SwitchDisplayType ->
                    ( case model.definitionDisplayType of
                        XRayView ->
                            { model | definitionDisplayType = InsightView }

                        InsightView ->
                            { model | definitionDisplayType = XRayView }
                    , Cmd.none
                    )

                ArgValueUpdated argName editorState ->
                    let
                        variables : InsightArgumentState -> Dict Name (Value () ())
                        variables argState =
                            argState
                                |> Dict.map (\_ arg -> arg.lastValidValue |> Maybe.withDefault (Value.Unit ()))

                        newArgState : InsightArgumentState
                        newArgState =
                            model.argStates |> Dict.insert argName editorState
                    in
                    ( { model
                        | argStates = newArgState
                        , insightViewState = { insightViewState | variables = variables newArgState }
                      }
                    , Cmd.none
                    )

        Filter filterMsg ->
            let
                homeState : HomeState
                homeState =
                    model.homeState

                filterState : FilterState
                filterState =
                    homeState.filterState
            in
            case filterMsg of
                SearchDefinition s ->
                    ( { model | homeState = { homeState | filterState = { filterState | searchText = s } } }
                    , Nav.replaceUrl model.key (filterStateToQueryParams { filterState | searchText = s })
                    )

                ToggleValues v ->
                    ( model
                    , Nav.replaceUrl model.key (filterStateToQueryParams { filterState | showValues = v })
                    )

                ToggleTypes t ->
                    ( model
                    , Nav.replaceUrl model.key (filterStateToQueryParams { filterState | showTypes = t })
                    )

                ModuleClicked path ->
                    ( model
                    , Nav.replaceUrl model.key (filterStateToQueryParams { filterState | moduleClicked = path })
                    )

        Testing testingMsg ->
            case testingMsg of
                DescriptionUpdated _ _ ->
                    Debug.todo "branch 'FunctionDescriptionUpdated _ _' not implemented"

                DeleteTestCase _ ->
                    Debug.todo "branch 'FunctionDeleteTestCase _' not implemented"

                LoadTestCase inputTypes values ->
                    let
                        insightViewState : Morphir.Visual.Config.VisualState
                        insightViewState =
                            model.insightViewState

                        dictfromRecord : { a | keys : List comparable, vals : List b } -> Dict comparable b
                        dictfromRecord { keys, vals } =
                            Dict.fromList <| List.map2 Tuple.pair keys vals

                        newVariables : Dict Name RawValue
                        newVariables =
                            dictfromRecord
                                { keys = List.map Tuple.first inputTypes
                                , vals = values
                                }

                        newArgState : Type () -> RawValue -> ValueEditor.EditorState
                        newArgState tpe val =
                            ValueEditor.initEditorState (IR.fromDistribution getDistribution) tpe (Just val)

                        newArgStates : Dict Name ValueEditor.EditorState
                        newArgStates =
                            dictfromRecord
                                { keys = List.map Tuple.first inputTypes
                                , vals = List.map2 newArgState (List.map Tuple.second inputTypes) values
                                }
                    in
                    ( { model
                        | argStates = newArgStates
                        , insightViewState = { insightViewState | variables = newVariables }
                      }
                    , Cmd.none
                    )

                SaveTestSuite fQName testCase ->
                    let
                        newTestSuite =
                            Dict.insert fQName
                                (Array.push testCase (Dict.get fQName model.testSuite |> Maybe.withDefault Array.empty))
                                model.testSuite
                    in
                    ( { model | testSuite = newTestSuite }
                    , httpSaveTestSuite (IR.fromDistribution getDistribution) (toStoredTestSuite newTestSuite)
                    )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- ROUTE


{-| Parses the ulr if it's in one of the following formats

    topUrlWithoutHome --"/"

    topUrlWithHome --"/home"

    packageUrl --"/home/<Package.Name>"

    moduleUrl --"/home/<Package.Name>/<Module.Name>"

    definitionUrl --"/home/<Package.Name>/<Module.Name>/<Definition>"

-}
routeParser : Parser (ModelUpdate -> a) a
routeParser =
    UrlParser.oneOf [ topUrlWithoutHome, topUrlWithHome, packageUrl, moduleUrl, definitionUrl ]


{-| Creates a modelUpdate function based on the data parsed from the url, which tells the model how to change
-}
updateHomeState : String -> String -> String -> FilterState -> ModelUpdate
updateHomeState pack mod def filterState =
    let
        toTypeOrValue : String -> String -> Maybe Definition
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
            { model | homeState = newState, insightViewState = emptyVisualState, argStates = Dict.empty }

        -- When selecting a definition, we should not change the selected module, once the user explicitly selected one
        keepOrChangeSelectedModule : ( List Path, List Name )
        keepOrChangeSelectedModule =
            if filterState.moduleClicked == pack then
                ( urlFragmentToNodePath "", [] )

            else
                ifThenElse (filterState.moduleClicked == "")
                    ( urlFragmentToNodePath mod, Path.fromString mod )
                    ( urlFragmentToNodePath filterState.moduleClicked, Path.fromString filterState.moduleClicked )
    in
    -- initial state, nothing is selected
    if pack == "" then
        updateModel
            { selectedPackage = Nothing
            , selectedModule = Nothing
            , selectedDefinition = Nothing
            , filterState = filterState
            }
        -- a top level package is selected

    else if mod == "" then
        updateModel
            { selectedPackage = Just (Path.fromString pack)
            , selectedModule = Just ( urlFragmentToNodePath mod, [] )
            , selectedDefinition = Nothing
            , filterState = filterState
            }
        -- a module is selected

    else if def == "" then
        updateModel
            { selectedPackage = Just (Path.fromString pack)
            , selectedModule = Just ( urlFragmentToNodePath mod, Path.fromString mod )
            , selectedDefinition = Nothing
            , filterState = filterState
            }
        -- a definition is selected

    else
        updateModel
            { selectedPackage = Just (Path.fromString pack)
            , selectedModule = Just keepOrChangeSelectedModule
            , selectedDefinition = toTypeOrValue mod def
            , filterState = filterState
            }


{-| Applies the routeParser to the url, resulting in a ModelUpdate function, which tells the model how to change
-}
toRoute : Url -> ModelUpdate
toRoute url =
    UrlParser.parse routeParser url
        |> Maybe.withDefault identity


topUrl : Parser (FilterState -> ModelUpdate) b -> Parser (b -> a) a
topUrl =
    UrlParser.map
        (\filter ->
            updateHomeState "" "" "" filter
        )


{-| Parse urls that look like this:

"/home"

-}
topUrlWithHome : Parser (ModelUpdate -> a) a
topUrlWithHome =
    topUrl <|
        UrlParser.s "home"
            <?> queryParams


{-| Parse urls that look like this:

"/"

-}
topUrlWithoutHome : Parser (ModelUpdate -> a) a
topUrlWithoutHome =
    topUrl <|
        UrlParser.top
            <?> queryParams


{-| Parse urls that look like this:

"/home/<Package.Name>"

-}
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


{-| Parse urls that look like this:

"home/<Package.Name>/<Module.Name>"

-}
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


{-| Parse urls that look like this:

--"/home/<Package.Name>/<Module.Name>/Definition>"

-}
definitionUrl : Parser (ModelUpdate -> a) a
definitionUrl =
    UrlParser.map updateHomeState
        (UrlParser.s "home"
            </> UrlParser.string
            </> UrlParser.string
            </> UrlParser.string
            <?> queryParams
        )


{-| Parses the following query parameters

"search"
"showValues"
"showTypes"

-}
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

        moduleClicked : Query.Parser String
        moduleClicked =
            Query.string "moduleClicked" |> Query.map (Maybe.withDefault "")
    in
    Query.map4 FilterState search showValues showTypes moduleClicked


{-| Turns the model's current filter state into a query parameter string to be used in building the url
-}
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

        moduleClicked =
            ifThenElse (filterState.moduleClicked == "") "" ("&moduleClicked=" ++ filterState.moduleClicked)
    in
    "?" ++ search ++ filterValues ++ filterTypes ++ moduleClicked



-- VIEW


{-| Top level function to render the current ui state
-}
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
            ]
            (column
                [ width fill
                , height fill
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
                    ]
                    (viewBody model)
                ]
            )
        ]
    }


{-| Returns the site header element
-}
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


{-| Display server errors on the UI
-}
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


{-| Display the main part of home UI if the IR has loaded
-}
viewBody : Model -> Element Msg
viewBody model =
    case model.irState of
        IRLoading ->
            text "Loading the IR ..."

        IRLoaded (Library packageName _ packageDef) ->
            viewHome model packageName packageDef


{-| Display the home UI
-}
viewHome : Model -> PackageName -> Package.Definition () (Type ()) -> Element Msg
viewHome model packageName packageDef =
    let
        gray : Element.Color
        gray =
            rgb 0.9 0.9 0.9

        morphIrBlue : Element.Color
        morphIrBlue =
            rgb 0 0.639 0.882

        lightMorphIrBlue : Element.Color
        lightMorphIrBlue =
            rgba 0 0.639 0.882 0.6

        morphIrOrange : Element.Color
        morphIrOrange =
            rgb 1 0.411 0

        lightMorphIrOrange : Element.Color
        lightMorphIrOrange =
            rgba 1 0.411 0 0.6

        -- Styles to make the module tree and the definition list
        listStyles : List (Element.Attribute msg)
        listStyles =
            [ width fill
            , Background.color model.theme.colors.lightest
            , Border.rounded 3
            , paddingXY (model.theme |> Theme.scaled 3) (model.theme |> Theme.scaled -1)
            ]

        -- Display a single selected definition on the ui
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

        -- Given a module name and a module definition, returns a list of tuples with the module's definitions, and their human readable form
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

                createElementKey definition =
                    case definition of
                        Type ( mname, tname ) ->
                            (mname |> List.map Name.toTitleCase |> String.join ".") ++ Name.toTitleCase tname

                        Value ( mname, vname ) ->
                            (mname |> List.map Name.toTitleCase |> String.join ".") ++ Name.toTitleCase vname

                types : List ( Definition, Element Msg )
                types =
                    moduleDef.types
                        |> Dict.toList
                        |> List.map
                            (\( typeName, _ ) ->
                                ( Type ( moduleName, typeName )
                                , createUiElement (Element.Keyed.el [ Font.color lightMorphIrBlue ] ( createElementKey <| Type ( moduleName, typeName ), text "ⓣ " )) (Type ( moduleName, typeName )) typeName Name.toTitleCase
                                )
                            )

                values : List ( Definition, Element Msg )
                values =
                    moduleDef.values
                        |> Dict.toList
                        |> List.map
                            (\( valueName, _ ) ->
                                ( Value ( moduleName, valueName )
                                , createUiElement (Element.Keyed.el [ Font.color lightMorphIrOrange ] ( createElementKey <| Value ( moduleName, valueName ), text "ⓥ " )) (Value ( moduleName, valueName )) valueName Name.toCamelCase
                                )
                            )
            in
            ifThenElse model.homeState.filterState.showValues values [] ++ ifThenElse model.homeState.filterState.showTypes types []

        -- Returns the alphabetically ordered, optionally filtered list of definitions in the currently selected module
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

        -- Creates a text input to search defintions by name
        definitionFilter : Element Msg
        definitionFilter =
            Element.Input.search
                [ height fill
                , Font.size (model.theme |> Theme.scaled 2)
                , padding (model.theme |> Theme.scaled -2)
                , width (fillPortion 7)
                ]
                { onChange = Filter << SearchDefinition
                , text = model.homeState.filterState.searchText
                , placeholder = Just (Element.Input.placeholder [] (text "Search for a definition"))
                , label = Element.Input.labelHidden "Search"
                }

        -- Creates a checkbox to filter out values from the definition list
        valueCheckbox : Element Msg
        valueCheckbox =
            Element.Input.checkbox
                [ width (fillPortion 2) ]
                { onChange = Filter << ToggleValues
                , checked = model.homeState.filterState.showValues
                , icon = Element.Input.defaultCheckbox
                , label = Element.Input.labelLeft [] (text "values:")
                }

        -- Creates a checkbox to filter out types from the definition list
        typeCheckbox : Element Msg
        typeCheckbox =
            Element.Input.checkbox
                [ width (fillPortion 2) ]
                { onChange = Filter << ToggleTypes
                , checked = model.homeState.filterState.showTypes
                , icon = Element.Input.defaultCheckbox
                , label = Element.Input.labelLeft [] (text "types:")
                }

        -- Creates a checkbox to open and close the module tree
        toggleModulesMenu : Element Msg
        toggleModulesMenu =
            Element.Input.button
                [ padding 7
                , Background.color <| ifThenElse model.showModules lightMorphIrBlue lightMorphIrOrange
                , Border.rounded 3
                , Font.color model.theme.colors.lightest
                , Font.bold
                , Font.size (model.theme |> Theme.scaled 2)
                , mouseOver [ Background.color <| ifThenElse model.showModules morphIrBlue morphIrOrange ]
                ]
                { onPress = Just (UI ToggleModulesMenu)
                , label = row [ spacing (model.theme |> Theme.scaled -6) ] [ el [ width (px 20) ] <| text <| ifThenElse model.showModules "🗁" "🗀", text "Modules" ]
                }

        -- Creates a checkbox to open and close the definitions list
        toggleDefinitionsMenu : Element Msg
        toggleDefinitionsMenu =
            Element.Input.button
                [ padding 7
                , Background.color <| ifThenElse model.showDefinitions lightMorphIrBlue lightMorphIrOrange
                , Border.rounded 3
                , Font.color model.theme.colors.lightest
                , Font.bold
                , Font.size (model.theme |> Theme.scaled 2)
                , mouseOver [ Background.color <| ifThenElse model.showDefinitions morphIrBlue morphIrOrange ]
                ]
                { onPress = Just (UI ToggleDefinitionsMenu)
                , label = row [ spacing (model.theme |> Theme.scaled -6) ] [ el [ width (px 20) ] <| text <| ifThenElse model.showDefinitions "🗁" "🗀", text "Definitions" ]
                }

        -- A document tree like view of the modules in the current package
        moduleTree : Element Msg
        moduleTree =
            el
                (listStyles ++ [ height fill, scrollbars ])
                (TreeLayout.view TreeLayout.defaultTheme
                    { onCollapse = UI << CollapseModule
                    , onExpand = UI << ExpandModule
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

        -- A path to the currently selected module in an easily readable format
        pathToSelectedModule : String
        pathToSelectedModule =
            case model.homeState.selectedModule |> Maybe.map Tuple.second of
                Just moduleName ->
                    "> " ++ pathToDisplayString moduleName

                _ ->
                    ">"

        -- Second column on the UI, the list of definitions in a module
        definitionList : Element Msg
        definitionList =
            column
                [ Background.color gray
                , height fill
                , width (ifThenElse model.showModules (fillPortion 3) fill)
                , spacing (model.theme |> Theme.scaled -4)
                , clipX
                ]
                [ row
                    [ width fill
                    , spacing (model.theme |> Theme.scaled 1)
                    , height <| fillPortion 1
                    ]
                    [ definitionFilter, row [ alignRight, spacing (model.theme |> Theme.scaled 1) ] [ valueCheckbox, typeCheckbox ] ]
                , row [ width fill, height <| fillPortion 1, Font.bold, paddingXY 5 0 ] [ Theme.ellipseText pathToSelectedModule ]
                , Element.Keyed.row ([ width fill, height <| fillPortion 23, scrollbars ] ++ listStyles) [ ( "definitions", viewDefinitionLabels (model.homeState.selectedModule |> Maybe.map Tuple.second) ) ]
                ]

        toggleDisplayType : Element Msg
        toggleDisplayType =
            let
                xrayOrInsight a b =
                    case model.definitionDisplayType of
                        XRayView ->
                            a

                        InsightView ->
                            b
            in
            Element.Input.button
                [ padding 7
                , Background.color <| xrayOrInsight lightMorphIrBlue lightMorphIrOrange
                , Border.rounded 3
                , Font.color model.theme.colors.lightest
                , Font.bold
                , Font.size (model.theme |> Theme.scaled 2)
                , mouseOver [ Background.color <| xrayOrInsight morphIrBlue morphIrOrange ]
                ]
                { onPress = Just (Insight SwitchDisplayType)
                , label = row [ spacing (model.theme |> Theme.scaled -6) ] [ text <| "Switch to " ++ xrayOrInsight "InsightView" "XRayView" ]
                }
    in
    row [ width fill, height fill, Background.color gray, spacing 10 ]
        [ column
            [ width
                (ifThenElse model.showDefinitions
                    (ifThenElse model.showModules (fillPortion 5) (fillPortion 3))
                    (fillPortion 1)
                )
            , height fill
            , paddingXY 0 (model.theme |> Theme.scaled -3)
            , clipX
            ]
            [ row
                [ height fill
                , width fill
                , spacing <| ifThenElse model.showModules 10 0
                , clipY
                ]
                [ row
                    [ Background.color gray
                    , height fill
                    , width (ifThenElse model.showModules (fillPortion 2) (px 40))
                    , clipX
                    ]
                    [ row [ alignTop, rotate (degrees -90), width (px 40), moveDown 182, padding (model.theme |> Theme.scaled -6), spacing (model.theme |> Theme.scaled -6) ] [ toggleDefinitionsMenu, toggleModulesMenu ]
                    , ifThenElse model.showModules moduleTree none
                    ]
                , ifThenElse model.showDefinitions definitionList none
                ]
            ]
        , column
            [ height fill
            , width
                (ifThenElse model.showDefinitions
                    (ifThenElse model.showModules (fillPortion 6) (fillPortion 7))
                    (fillPortion 46)
                )
            , Background.color model.theme.colors.lightest
            , scrollbars
            ]
            [ ifThenElse (model.homeState.selectedDefinition == Nothing)
                (dependencyGraph model.homeState.selectedModule model.repo)
                (column
                    [ height (fillPortion 2), paddingEach { bottom = 3, top = model.theme |> Theme.scaled 1, left = model.theme |> Theme.scaled 1, right = 0 }, width fill, spacing (model.theme |> Theme.scaled 1) ]
                    [ viewDefinition model.homeState.selectedDefinition
                    , toggleDisplayType
                    , el [ height fill, width fill, scrollbars ]
                        (viewDefinitionDetails model)
                    ]
                )
            ]
        ]


{-| Display detailed information of a Type on the UI
-}
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


{-| Display detailed information of a Value on the UI
-}
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
        (ifThenElse (docs == "") "[ This definition has no associated documentation. ]" docs)
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


{-| Display a Definition with it's name and path as a clickable UI element with a url pointing to the Definition
-}
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


{-| Display a TreeLayout of clickable module names in the given package, with urls pointing to the give module
-}
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

        handleClick : Path -> Msg
        handleClick path =
            Filter (ModuleClicked <| Path.toString Name.toTitleCase "." path)
    in
    TreeLayout.Node
        (\_ ->
            case currentModuleName of
                Just name ->
                    link [ pointer, onClick (handleClick parentModule) ]
                        { label = text (name |> nameToTitleText)
                        , url = pathToFullUrl [ packageName, parentModule ] ++ filterStateToQueryParams model.homeState.filterState
                        }

                Nothing ->
                    link [ pointer, onClick (handleClick packageName) ] { label = text (pathToUrl packageName), url = pathToFullUrl [ packageName ] ++ filterStateToQueryParams model.homeState.filterState }
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


{-| Given a definition, return it's name
-}
definitionName : Definition -> Name
definitionName definition =
    case definition of
        Value ( _, valueName ) ->
            valueName

        Type ( _, typeName ) ->
            typeName


{-| Displays the inner workings of the selected Definition
-}
viewDefinitionDetails : Model -> Element Msg
viewDefinitionDetails model =
    let
        insightViewConfig : IR -> Morphir.Visual.Config.Config Msg
        insightViewConfig ir =
            let
                referenceClicked : FQName -> Bool -> Msg
                referenceClicked fqname t =
                    Insight (ExpandReference fqname t)

                hoverOver : Int -> Maybe RawValue -> Msg
                hoverOver index value =
                    Insight (ExpandVariable index value)
            in
            Morphir.Visual.Config.fromIR
                ir
                model.insightViewState
                { onReferenceClicked = referenceClicked
                , onHoverOver = hoverOver
                , onHoverLeave = Insight << ShrinkVariable
                }

        viewArgumentEditors : IR -> InsightArgumentState -> List ( Name, a, Type () ) -> Element Msg
        viewArgumentEditors ir argState inputTypes =
            inputTypes
                |> List.map
                    (\( argName, _, argType ) ->
                        ( argName
                        , ValueEditor.view ir
                            argType
                            (Insight << ArgValueUpdated argName)
                            (argState |> Dict.get argName |> Maybe.withDefault (ValueEditor.initEditorState ir argType Nothing))
                        )
                    )
                |> FieldList.view

        saveTestcaseButton : FQName -> TestCase -> Element Msg
        saveTestcaseButton fqName testCase =
            let
                saveMsg =
                    Testing (SaveTestSuite fqName testCase)
            in
            Element.Input.button
                [ padding 7
                , Border.rounded 3
                , Background.color model.theme.colors.darkest
                , Font.color model.theme.colors.lightest
                , Font.bold
                , Font.size (model.theme |> Theme.scaled 2)
                ]
                { onPress = Just saveMsg
                , label = row [ spacing (model.theme |> Theme.scaled -6) ] [ text "Save Test" ]
                }

        viewActualOutput : Theme -> IR -> TestCase -> FQName -> Element Msg
        viewActualOutput theme ir testCase fQName =
            Common.viewAsCard theme
                (el [ Font.bold, Font.size (theme |> Theme.scaled 2), spacing 5, padding 5 ] (text "ACTUAL OUTPUT"))
                (case evaluateOutput ir testCase.inputs fQName of
                    Ok rawValue ->
                        el [ Font.heavy, Font.color theme.colors.darkest ] (viewRawValue (insightViewConfig ir) ir rawValue)

                    Err error ->
                        text "Invalid inputs"
                )

        evaluateOutput : IR -> List RawValue -> FQName -> Result Error RawValue
        evaluateOutput ir inputs fQName =
            evaluateFunctionValue SDK.nativeFunctions ir fQName inputs

        viewRawValue : Morphir.Visual.Config.Config Msg -> IR -> RawValue -> Element Msg
        viewRawValue config ir rawValue =
            case fromRawValue ir rawValue of
                Ok typedValue ->
                    el [ spacing 5, padding 5 ] (ViewValue.viewValue config typedValue)

                Err error ->
                    el [ centerX, centerY ] (text (Infer.typeErrorToMessage error))

        scenarios : FQName -> Distribution -> List ( Name, a, Type () ) -> Element Msg
        scenarios fQName distribution inputTypes =
            let
                ir : IR
                ir =
                    IR.fromDistribution distribution

                listOfTestcases : Array TestCase
                listOfTestcases =
                    Dict.get fQName model.testSuite |> Maybe.withDefault Array.empty

                displayValue : RawValue -> Element Msg
                displayValue t =
                    viewRawValue (insightViewConfig ir) ir t

                evaluate : TestCase -> Element.Color
                evaluate testCase =
                    case evaluateOutput ir testCase.inputs fQName of
                        Ok rawValue ->
                            if rawValue == testCase.expectedOutput then
                                model.theme.colors.positive

                            else
                                model.theme.colors.negative

                        Err _ ->
                            model.theme.colors.negative

                displayTestCase : ( Int, TestCase ) -> Element Msg
                displayTestCase ( index, testCase ) =
                    let
                        loadTestCaseMsg : Msg
                        loadTestCaseMsg =
                            Testing (LoadTestCase (List.map (\( name, _, tpe ) -> ( name, tpe )) inputTypes) testCase.inputs)
                    in
                    row
                        [ Background.color <| evaluate testCase
                        , Border.solid
                        , Border.color model.theme.colors.lightest
                        , Border.width 2
                        , onClick loadTestCaseMsg
                        , pointer
                        , mouseOver [ Border.color model.theme.colors.darkest ]
                        ]
                        ([ text " description: ", text testCase.description, text ", inputs:" ] ++ List.map displayValue testCase.inputs ++ [ text ", expected output:", displayValue testCase.expectedOutput ])
            in
            column [ spacing 4 ] (text "Test Cases" :: List.map displayTestCase (Array.toIndexedList listOfTestcases))
    in
    case model.irState of
        IRLoaded ((Library packageName _ packageDef) as distribution) ->
            case model.homeState.selectedDefinition of
                Just selectedDefinition ->
                    case selectedDefinition of
                        Value ( moduleName, valueName ) ->
                            case packageDef.modules |> Dict.get moduleName of
                                Just acmoduledef ->
                                    acmoduledef.value.values
                                        |> Dict.get valueName
                                        |> Maybe.map .value
                                        |> Maybe.map .value
                                        |> Maybe.andThen
                                            (\valueDef ->
                                                let
                                                    fullyQualifiedName : ( PackageName, ModuleName, Name )
                                                    fullyQualifiedName =
                                                        ( packageName, moduleName, valueName )

                                                    ir : IR
                                                    ir =
                                                        IR.fromDistribution distribution

                                                    saveButton : Element Msg
                                                    saveButton =
                                                        case evaluateOutput ir (Dict.values model.insightViewState.variables) fullyQualifiedName of
                                                            Ok rawValue ->
                                                                saveTestcaseButton
                                                                    fullyQualifiedName
                                                                    { description = "", expectedOutput = rawValue, inputs = Dict.values model.insightViewState.variables }

                                                            Err _ ->
                                                                none
                                                in
                                                case model.definitionDisplayType of
                                                    XRayView ->
                                                        Just <| XRayView.viewValueDefinition (XRayView.viewType <| pathToUrl) valueDef

                                                    InsightView ->
                                                        Just <|
                                                            column
                                                                [ width fill, height fill, spacing 20 ]
                                                                [ viewArgumentEditors ir model.argStates valueDef.inputTypes
                                                                , ViewValue.viewDefinition (insightViewConfig ir) fullyQualifiedName valueDef
                                                                , viewActualOutput
                                                                    model.theme
                                                                    ir
                                                                    { description = "", expectedOutput = Value.toRawValue <| Value.Tuple () [], inputs = Dict.values model.insightViewState.variables }
                                                                    fullyQualifiedName
                                                                , saveButton
                                                                , scenarios fullyQualifiedName distribution valueDef.inputTypes
                                                                ]
                                            )
                                        |> Maybe.withDefault none

                                Nothing ->
                                    none

                        Type _ ->
                            none

                Nothing ->
                    none

        IRLoading ->
            none
