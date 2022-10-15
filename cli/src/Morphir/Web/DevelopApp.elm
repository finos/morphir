module Morphir.Web.DevelopApp exposing (IRState(..), Model, Msg(..), ServerState(..), httpMakeModel, init, main, routeParser, subscriptions, update, view, viewBody, viewHeader)

import Array exposing (Array)
import Array.Extra
import Browser
import Browser.Navigation as Nav
import Dict exposing (Dict)
import Element
    exposing
        ( Element
        , above
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
        , image
        , layout
        , link
        , maximum
        , mouseOver
        , moveDown
        , none
        , padding
        , paddingEach
        , paddingXY
        , pointer
        , px
        , rgb
        , rgba
        , rotate
        , row
        , scrollbars
        , shrink
        , spacing
        , text
        , width
        )
import Element.Background as Background
import Element.Border as Border
import Element.Events exposing (onClick)
import Element.Font as Font
import Element.Input
import Element.Keyed
import Http exposing (Error(..), emptyBody, jsonBody)
import Morphir.Correctness.Codec exposing (decodeTestSuite, encodeTestSuite)
import Morphir.Correctness.Test exposing (TestCase, TestSuite)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Distribution.Codec as DistributionCodec
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Repo as Repo exposing (Repo)
import Morphir.IR.SDK as SDK exposing (packageName)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, Value(..))
import Morphir.Type.Infer as Infer
import Morphir.Value.Error exposing (Error)
import Morphir.Value.Interpreter exposing (evaluateFunctionValue)
import Morphir.Visual.Common exposing (nameToText, nameToTitleText, pathToDisplayString, pathToFullUrl, pathToUrl, tooltip)
import Morphir.Visual.Components.Card as Card
import Morphir.Visual.Components.FieldList as FieldList
import Morphir.Visual.Components.TabsComponent exposing (TabsComponentConfig, tabsComponent)
import Morphir.Visual.Components.TreeLayout as TreeLayout
import Morphir.Visual.Config exposing (DrillDownFunctions(..), ExpressionTreePath, PopupScreenRecord, addToDrillDown, removeFromDrillDown)
import Morphir.Visual.EnrichedValue exposing (fromRawValue)
import Morphir.Visual.Theme as Theme exposing (Theme)
import Morphir.Visual.ValueEditor as ValueEditor
import Morphir.Visual.ViewType as ViewType
import Morphir.Visual.ViewValue as ViewValue
import Morphir.Visual.XRayView as XRayView
import Morphir.Web.DevelopApp.Common exposing (ifThenElse, urlFragmentToNodePath)
import Morphir.Web.Graph.DependencyGraph exposing (dependencyGraph)
import Ordering
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
    , argStates : InsightArgumentState
    , expandedValues : Dict ( FQName, Name ) (Value.Definition () (Type ()))
    , selectedTestcaseIndex : Int
    , testDescription : String
    , activeTabIndex : Int
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
            , argStates = Dict.empty
            , expandedValues = Dict.empty
            , selectedTestcaseIndex = -1
            , testDescription = ""
            , activeTabIndex = 0
            }
    in
    ( toRoute url initModel
    , Cmd.batch [ httpMakeModel ]
    )


emptyVisualState : Morphir.Visual.Config.VisualState
emptyVisualState =
    { theme = Theme.fromConfig Nothing
    , variables = Dict.empty
    , highlightState = Nothing
    , popupVariables =
        { variableIndex = 0
        , variableValue = Nothing
        , nodePath = []
        }
    , drillDownFunctions = DrillDownFunctions Dict.empty
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
    = DeleteTestCase FQName Int
    | SaveTestSuite FQName TestCase
    | LoadTestCase (List ( Name, Type () )) (List (Maybe RawValue)) String Int
    | UpdateTestCase FQName TestCase
    | UpdateDescription String


type NavigationMsg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url


type UIMsg
    = ToggleModulesMenu
    | ToggleDefinitionsMenu
    | ExpandModule (TreeLayout.NodePath ModuleName)
    | CollapseModule (TreeLayout.NodePath ModuleName)
    | SwitchTab Int


type FilterMsg
    = SearchDefinition String
    | ToggleValues Bool
    | ToggleTypes Bool
    | ModuleClicked String


type InsightMsg
    = ExpandReference FQName Int ExpressionTreePath
    | ShrinkReference FQName Int ExpressionTreePath
    | ExpandVariable Int (List Int) (Maybe RawValue)
    | ShrinkVariable Int (List Int)
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

        fromStoredTestSuite : Dict FQName (List TestCase) -> Dict FQName (Array TestCase)
        fromStoredTestSuite testSuite =
            Dict.fromList (List.map (\( k, v ) -> ( k, Array.fromList v )) (Dict.toList testSuite))

        toStoredTestSuite : Dict FQName (Array TestCase) -> Dict FQName (List TestCase)
        toStoredTestSuite testSuite =
            Dict.fromList
                (List.map
                    (\( k, v ) ->
                        ( k
                        , Array.toList v
                            -- the interpreter and insightViewState needs Unit in places where no input is given, but we can't encode a value that does not match the parameter type
                            |> List.map (\testCase -> { testCase | inputs = List.map (\i -> ifThenElse (i == Just (Value.Unit ())) Nothing i) testCase.inputs })
                        )
                    )
                    (Dict.toList testSuite)
                )
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
            let
                irLoaded : IRState
                irLoaded =
                    IRLoaded distribution

                initialArgumentStates : InsightArgumentState
                initialArgumentStates =
                    initArgumentStates irLoaded model.homeState.selectedDefinition
            in
            case Repo.fromDistribution distribution of
                Ok r ->
                    ( { model | irState = irLoaded, repo = r, argStates = initialArgumentStates, insightViewState = initInsightViewState initialArgumentStates }
                    , httpTestModel (IR.fromDistribution distribution)
                    )

                Err _ ->
                    ( { model
                        | irState = irLoaded
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

                SwitchTab tabIndex ->
                    ( { model | activeTabIndex = tabIndex }, Cmd.none )

        ServerGetTestsResponse testSuite ->
            ( { model | testSuite = fromStoredTestSuite testSuite }, Cmd.none )

        Insight insightMsg ->
            let
                insightViewState : Morphir.Visual.Config.VisualState
                insightViewState =
                    model.insightViewState
            in
            case insightMsg of
                ExpandReference fQName id nodePath ->
                    case fQName of
                        ( [ [ "morphir" ], [ "s", "d", "k" ] ], _, _ ) ->
                            ( model, Cmd.none )

                        _ ->
                            ( { model
                                | insightViewState =
                                    { insightViewState
                                        | drillDownFunctions = DrillDownFunctions (addToDrillDown insightViewState.drillDownFunctions id nodePath)
                                    }
                              }
                            , Cmd.none
                            )

                ShrinkReference fQName id nodePath ->
                    case fQName of
                        ( [ [ "morphir" ], [ "s", "d", "k" ] ], _, _ ) ->
                            ( model, Cmd.none )

                        _ ->
                            ( { model
                                | insightViewState =
                                    { insightViewState
                                        | drillDownFunctions = DrillDownFunctions (removeFromDrillDown insightViewState.drillDownFunctions id nodePath)
                                    }
                              }
                            , Cmd.none
                            )

                ExpandVariable varIndex nodePath maybeRawValue ->
                    ( { model | insightViewState = { insightViewState | popupVariables = PopupScreenRecord varIndex maybeRawValue nodePath } }, Cmd.none )

                ShrinkVariable varIndex nodePath ->
                    ( { model | insightViewState = { insightViewState | popupVariables = PopupScreenRecord varIndex Nothing nodePath } }, Cmd.none )


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
            let
                initalArgState : InsightArgumentState
                initalArgState =
                    initArgumentStates model.irState model.homeState.selectedDefinition
            in
            case testingMsg of
                UpdateDescription description ->
                    ( { model | testDescription = description }, Cmd.none )

                UpdateTestCase fQName testCase ->
                    let
                        newTestCase =
                            { testCase | description = model.testDescription }

                        newTestSuite : Dict FQName (Array TestCase)
                        newTestSuite =
                            Dict.insert fQName
                                (Array.Extra.update model.selectedTestcaseIndex (always newTestCase) (Dict.get fQName model.testSuite |> Maybe.withDefault Array.empty))
                                model.testSuite
                    in
                    ( { model | testSuite = newTestSuite, selectedTestcaseIndex = -1, testDescription = "", argStates = initalArgState, insightViewState = initInsightViewState initalArgState }
                    , httpSaveTestSuite (IR.fromDistribution getDistribution) (toStoredTestSuite newTestSuite) (toStoredTestSuite model.testSuite)
                    )

                DeleteTestCase fQName index ->
                    let
                        newTestSuite : Dict FQName (Array TestCase)
                        newTestSuite =
                            Dict.insert fQName
                                (Array.Extra.removeAt index (Dict.get fQName model.testSuite |> Maybe.withDefault Array.empty))
                                model.testSuite
                    in
                    ( { model | testSuite = newTestSuite, selectedTestcaseIndex = ifThenElse (model.selectedTestcaseIndex == index) -1 model.selectedTestcaseIndex }
                    , httpSaveTestSuite (IR.fromDistribution getDistribution) (toStoredTestSuite newTestSuite) (toStoredTestSuite model.testSuite)
                    )

                LoadTestCase inputTypes values description index ->
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
                                , vals = List.map (Maybe.withDefault (Value.Unit ())) values
                                }

                        newArgState : Type () -> Maybe RawValue -> ValueEditor.EditorState
                        newArgState tpe val =
                            ValueEditor.initEditorState (IR.fromDistribution getDistribution) tpe val

                        newArgStates : InsightArgumentState
                        newArgStates =
                            dictfromRecord
                                { keys = List.map Tuple.first inputTypes
                                , vals = List.map2 newArgState (List.map Tuple.second inputTypes) values
                                }
                    in
                    ( { model
                        | argStates = newArgStates
                        , insightViewState = { insightViewState | variables = newVariables }
                        , selectedTestcaseIndex = index
                        , testDescription = description
                      }
                    , Cmd.none
                    )

                SaveTestSuite fQName testCase ->
                    let
                        newTestCase =
                            { testCase | description = model.testDescription }

                        newTestSuite : Dict FQName (Array TestCase)
                        newTestSuite =
                            Dict.insert fQName
                                (Array.push newTestCase (Dict.get fQName model.testSuite |> Maybe.withDefault Array.empty))
                                model.testSuite
                    in
                    ( { model | testSuite = newTestSuite, selectedTestcaseIndex = -1, testDescription = "", argStates = initalArgState, insightViewState = initInsightViewState initalArgState }
                    , httpSaveTestSuite (IR.fromDistribution getDistribution) (toStoredTestSuite newTestSuite) (toStoredTestSuite model.testSuite)
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
            let
                definitionArgs : ( ModuleName, Name )
                definitionArgs =
                    ( Path.fromString m, Name.fromString d )
            in
            case String.uncons d of
                Just ( first, _ ) ->
                    if Char.isLower first then
                        Just (Value definitionArgs)

                    else
                        Just (Type definitionArgs)

                _ ->
                    Nothing

        updateModel : HomeState -> Maybe Definition -> ModelUpdate
        updateModel newState maybeSelectedDefinition model =
            let
                initialArgState : InsightArgumentState
                initialArgState =
                    initArgumentStates model.irState maybeSelectedDefinition
            in
            { model | homeState = newState, insightViewState = initInsightViewState initialArgState, argStates = initialArgState, selectedTestcaseIndex = -1, testDescription = "" }

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
            Nothing
        -- a top level package is selected

    else if mod == "" then
        updateModel
            { selectedPackage = Just (Path.fromString pack)
            , selectedModule = Just ( urlFragmentToNodePath mod, [] )
            , selectedDefinition = Nothing
            , filterState = filterState
            }
            Nothing
        -- a module is selected

    else if def == "" then
        updateModel
            { selectedPackage = Just (Path.fromString pack)
            , selectedModule = Just ( urlFragmentToNodePath mod, Path.fromString mod )
            , selectedDefinition = Nothing
            , filterState = filterState
            }
            Nothing
        -- a definition is selected

    else
        updateModel
            { selectedPackage = Just (Path.fromString pack)
            , selectedModule = Just keepOrChangeSelectedModule
            , selectedDefinition = toTypeOrValue mod def
            , filterState = filterState
            }
            (toTypeOrValue mod def)


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
            [ width fill ]
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
            , Theme.borderRounded
            , paddingXY (model.theme |> Theme.scaled 3) (model.theme |> Theme.scaled -1)
            ]

        -- Display a single selected definition on the ui
        viewDefinition : Maybe Definition -> Element Msg
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
                                                    column []
                                                        [ viewValue model.theme moduleName valueName valueDef.value.value valueDef.value.doc ]
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
                                                    ViewType.viewType model.theme typeName typeDef.value.value typeDef.value.doc
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
                    viewAsLabel
                        model.theme
                        (model.homeState.selectedDefinition == Just definition)
                        icon
                        (text (nameToText name))
                        (pathToDisplayString moduleName)
                        (linkToDefinition name nameTransformation)

                createElementKey : List Name -> Name -> String
                createElementKey mname name =
                    (mname |> List.map Name.toTitleCase |> String.join ".") ++ Name.toTitleCase name

                types : List ( Definition, Element Msg )
                types =
                    moduleDef.types
                        |> Dict.toList
                        |> List.map
                            (\( typeName, _ ) ->
                                ( Type ( moduleName, typeName )
                                , createUiElement (Element.Keyed.el [ Font.color lightMorphIrBlue ] ( createElementKey moduleName typeName, text "ⓣ " )) (Type ( moduleName, typeName )) typeName Name.toTitleCase
                                )
                            )

                values : List ( Definition, Element Msg )
                values =
                    moduleDef.values
                        |> Dict.toList
                        |> List.map
                            (\( valueName, _ ) ->
                                ( Value ( moduleName, valueName )
                                , createUiElement (Element.Keyed.el [ Font.color lightMorphIrOrange ] ( createElementKey moduleName valueName, text "ⓥ " )) (Value ( moduleName, valueName )) valueName Name.toCamelCase
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
                [ Font.size (model.theme |> Theme.scaled 2)
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
                , Theme.borderRounded
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
                , Theme.borderRounded
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
        pathToSelectedModule =
            let
                subPaths : Path -> List Path
                subPaths path =
                    let
                        helper s xs =
                            case xs of
                                [] ->
                                    []

                                n :: ns ->
                                    helper (s ++ [ n ]) ns ++ [ s ]
                    in
                    (List.drop 1 <| List.reverse <| helper [] path) ++ [ path ]
            in
            case model.homeState.selectedModule |> Maybe.map Tuple.second of
                Just moduleName ->
                    subPaths moduleName
                        |> List.map
                            (\m ->
                                link
                                    [ pointer
                                    , onClick <| handleModuleClick m
                                    , width (maximum 100 shrink)
                                    , Border.color model.theme.colors.gray
                                    , Theme.borderBottom 1
                                    , mouseOver [ Border.color model.theme.colors.darkest ]
                                    ]
                                    { label = Theme.ellipseText <| " > " ++ (m |> List.reverse |> List.head |> Maybe.withDefault [ "" ] |> nameToTitleText)
                                    , url = pathToFullUrl [ packageName, m ] ++ filterStateToQueryParams model.homeState.filterState
                                    }
                            )

                _ ->
                    [ text ">" ]

        -- Second column on the UI, the list of definitions in a module
        definitionList : Element Msg
        definitionList =
            column
                [ Background.color model.theme.colors.gray
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
                , row [ width fill, height <| fillPortion 1, Font.bold, paddingXY 5 0 ]
                    pathToSelectedModule
                , Element.Keyed.row ([ width fill, height <| fillPortion 23, scrollbars ] ++ listStyles) [ ( "definitions", viewDefinitionLabels (model.homeState.selectedModule |> Maybe.map Tuple.second) ) ]
                ]
    in
    row [ width fill, height fill, Background.color model.theme.colors.gray, spacing 10 ]
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
                    [ Background.color model.theme.colors.gray
                    , height fill
                    , width (ifThenElse model.showModules (fillPortion 2) (px 40))
                    , clipX
                    ]
                    [ row [ alignTop, rotate (degrees -90), width (px 40), moveDown 165, padding (model.theme |> Theme.scaled -6), spacing (model.theme |> Theme.scaled -6) ] [ toggleDefinitionsMenu, toggleModulesMenu ]
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
                    [ scrollbars, height (fillPortion 2), paddingEach { bottom = 3, top = model.theme |> Theme.scaled 1, left = model.theme |> Theme.scaled 1, right = 0 }, width fill, spacing (model.theme |> Theme.scaled 1) ]
                    [ viewDefinition model.homeState.selectedDefinition
                    , el [ height fill, width fill, scrollbars ]
                        (viewDefinitionDetails model)
                    ]
                )
            ]
        ]


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
    Card.viewAsCard theme
        cardTitle
        (if isData then
            "value"

         else
            "calculation"
        )
        backgroundColor
        (ifThenElse (docs == "") "[ This definition has no associated documentation. ]" docs)
        none


{-| Display a Definition with its name and path as a clickable UI element with a url pointing to the Definition
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
        , Theme.borderBottom 1
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


httpSaveTestSuite : IR -> TestSuite -> TestSuite -> Cmd Msg
httpSaveTestSuite ir newTestSuite oldTestSuite =
    let
        encodedTestSuite =
            case encodeTestSuite ir newTestSuite of
                Ok encodedValue ->
                    jsonBody encodedValue

                Err _ ->
                    case encodeTestSuite ir oldTestSuite of
                        Ok fallBackEncoded ->
                            jsonBody fallBackEncoded

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
    in
    TreeLayout.Node
        (\_ ->
            case currentModuleName of
                Just name ->
                    link [ pointer, onClick (handleModuleClick parentModule) ]
                        { label = text (name |> nameToTitleText)
                        , url = pathToFullUrl [ packageName, parentModule ] ++ filterStateToQueryParams model.homeState.filterState
                        }

                Nothing ->
                    link [ pointer, onClick (handleModuleClick packageName) ] { label = text (pathToUrl packageName), url = pathToFullUrl [ packageName ] ++ filterStateToQueryParams model.homeState.filterState }
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


{-| Note which module we last clicked on
-}
handleModuleClick : Path -> Msg
handleModuleClick path =
    Filter (ModuleClicked <| Path.toString Name.toTitleCase "." path)


{-| Given a definition, return its name
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
                referenceClicked : FQName -> Int -> List Int -> Msg
                referenceClicked fQName id nodePath =
                    Insight (ExpandReference fQName id nodePath)

                referenceClosed : FQName -> Int -> List Int -> Msg
                referenceClosed fQName int nodePath =
                    Insight (ShrinkReference fQName int nodePath)

                hoverOver : Int -> List Int -> Maybe RawValue -> Msg
                hoverOver index nodePath value =
                    Insight (ExpandVariable index nodePath value)

                hoverLeave : Int -> List Int -> Msg
                hoverLeave index nodePath =
                    Insight (ShrinkVariable index nodePath)
            in
            Morphir.Visual.Config.fromIR
                ir
                model.insightViewState
                { onReferenceClicked = referenceClicked
                , onReferenceClose = referenceClosed
                , onHoverOver = hoverOver
                , onHoverLeave = hoverLeave
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

        buttonStyles : List (Element.Attribute msg)
        buttonStyles =
            [ padding 7
            , Theme.borderRounded
            , Background.color model.theme.colors.darkest
            , Font.color model.theme.colors.lightest
            , Font.bold
            , Font.size (model.theme |> Theme.scaled 2)
            ]

        saveTestcaseButton : FQName -> TestCase -> Element Msg
        saveTestcaseButton fqName testCase =
            let
                saveMsg : Msg
                saveMsg =
                    Testing (SaveTestSuite fqName testCase)
            in
            Element.Input.button
                buttonStyles
                { onPress = Just saveMsg
                , label = row [ spacing (model.theme |> Theme.scaled -6) ] [ text "Save as new testcase" ]
                }

        updateTestCaseButton : FQName -> TestCase -> Element Msg
        updateTestCaseButton fqName testCase =
            let
                updateMsg : Msg
                updateMsg =
                    Testing (UpdateTestCase fqName testCase)
            in
            Element.Input.button
                buttonStyles
                { onPress = Just updateMsg
                , label = row [ spacing (model.theme |> Theme.scaled -6) ] [ text <| "Update testcase #" ++ String.fromInt (model.selectedTestcaseIndex + 1) ]
                }

        descriptionInput : Element Msg
        descriptionInput =
            Element.Input.text
                [ Font.size (model.theme |> Theme.scaled 2)
                , padding (model.theme |> Theme.scaled -2)
                ]
                { onChange = Testing << UpdateDescription
                , text = model.testDescription
                , placeholder = Just (Element.Input.placeholder [] (text "Write a test description here..."))
                , label = Element.Input.labelHidden "Description"
                }

        viewActualOutput : Theme -> IR -> TestCase -> FQName -> Element Msg
        viewActualOutput theme ir testCase fQName =
            row [ spacing (model.theme |> Theme.scaled 2) ] <|
                ifThenElse (List.isEmpty testCase.inputs)
                    []
                    [ row [ Theme.borderRounded, Border.width 3, spacing (theme |> Theme.scaled 2), padding (theme |> Theme.scaled -2) ]
                        (case evaluateOutput ir testCase.inputs fQName of
                            Ok rawValue ->
                                case rawValue of
                                    Value.Unit () ->
                                        [ text "Not enough information. Maybe the output depends on an input you have not set yet?" ]

                                    expectedOutput ->
                                        [ el [ Font.bold, Font.size (theme |> Theme.scaled 2) ] (text "value:")
                                        , el [ Font.heavy, Font.color theme.colors.darkest ] (viewRawValue (insightViewConfig ir) ir rawValue)
                                        , ifThenElse (Dict.isEmpty model.argStates) none (saveTestcaseButton fQName { testCase | expectedOutput = expectedOutput })
                                        , ifThenElse (model.selectedTestcaseIndex < 0) none (updateTestCaseButton fQName { testCase | expectedOutput = expectedOutput })
                                        ]

                            Err _ ->
                                [ text "Invalid or missing inputs" ]
                        )
                    ]

        evaluateOutput : IR -> List (Maybe RawValue) -> FQName -> Result Error RawValue
        evaluateOutput ir inputs fQName =
            evaluateFunctionValue SDK.nativeFunctions ir fQName inputs

        viewRawValue : Morphir.Visual.Config.Config Msg -> IR -> RawValue -> Element Msg
        viewRawValue config ir rawValue =
            case fromRawValue ir rawValue of
                Ok typedValue ->
                    el [ centerY ] (ViewValue.viewValue config typedValue)

                Err error ->
                    el [ centerX, centerY ] (text (Infer.typeErrorToMessage error))

        scenarios : FQName -> IR -> List ( Name, a, Type () ) -> Element Msg
        scenarios fQName ir inputTypes =
            let
                listOfTestcases : Array TestCase
                listOfTestcases =
                    Dict.get fQName model.testSuite |> Maybe.withDefault Array.empty

                displayValue : RawValue -> Element Msg
                displayValue t =
                    viewRawValue (insightViewConfig ir) ir t

                inputNameList : List ( Int, String )
                inputNameList =
                    List.indexedMap (\i ( n, _, _ ) -> ( i, nameToText n )) inputTypes

                evaluate : TestCase -> Element.Color
                evaluate testCase =
                    case evaluateOutput ir testCase.inputs fQName of
                        Ok rawValue ->
                            if rawValue == testCase.expectedOutput then
                                model.theme.colors.positiveLight

                            else
                                model.theme.colors.negativeLight

                        Err _ ->
                            model.theme.colors.negative

                testsTable : Element Msg
                testsTable =
                    let
                        deleteButton : Int -> Element Msg
                        deleteButton index =
                            Element.Input.button
                                [ Border.width 1
                                , mouseOver [ Border.color model.theme.colors.darkest ]
                                , Background.color model.theme.colors.negativeLight
                                , Font.color model.theme.colors.lightest
                                , Font.size (model.theme |> Theme.scaled 5)
                                , pointer
                                , height fill
                                , Border.roundEach { topLeft = 0, bottomLeft = 0, topRight = 3, bottomRight = 3 }
                                ]
                                { onPress = Just <| Testing (DeleteTestCase fQName index)
                                , label = el [ centerX, centerY ] (text " 🗑 ")
                                }

                        myTooltip : String -> Element msg
                        myTooltip tooltipText =
                            if tooltipText == "" then
                                none

                            else
                                el
                                    [ Background.color model.theme.colors.darkest
                                    , Font.color model.theme.colors.lightest
                                    , padding (model.theme |> Theme.scaled -2)
                                    , Theme.borderRounded
                                    , Font.size (model.theme |> Theme.scaled 2)
                                    , Font.bold
                                    , Border.shadow
                                        { offset = ( 0, 3 ), blur = 6, size = 0, color = rgba 0 0 0 0.32 }
                                    ]
                                    (text tooltipText)

                        testRow : Int -> Int -> Int -> TestCase -> Element Msg
                        testRow columnIndex selfIndex maxIndex test =
                            let
                                loadTestCaseMsg : Msg
                                loadTestCaseMsg =
                                    Testing (LoadTestCase (List.map (\( name, _, tpe ) -> ( name, tpe )) inputTypes) test.inputs test.description selfIndex)

                                styles : List (Element.Attr () Msg)
                                styles =
                                    [ Background.color <| evaluate test
                                    , height fill
                                    , Border.widthXY 0 1
                                    , paddingXY (model.theme |> Theme.scaled -1) (model.theme |> Theme.scaled -5)
                                    , Border.color model.theme.colors.lightest
                                    , pointer
                                    , onClick loadTestCaseMsg
                                    , tooltip above (myTooltip test.description)
                                    ]

                                rowCell : Element Msg
                                rowCell =
                                    (Array.get columnIndex <| Array.fromList test.inputs) |> Maybe.withDefault Nothing |> Maybe.withDefault (Value.Unit ()) |> displayValue
                            in
                            -- first cell's left border should be rounded
                            if columnIndex == 0 then
                                el (styles ++ [ Border.roundEach { topLeft = 3, bottomLeft = 3, topRight = 0, bottomRight = 0 } ]) rowCell

                            else if columnIndex < maxIndex then
                                el styles rowCell
                                -- last cell's right border should be rounded, and should have the delete button

                            else
                                row [ width fill, height fill ]
                                    [ el (styles ++ [ paddingEach { right = model.theme |> Theme.scaled 7, left = 0, top = 0, bottom = 0 } ])
                                        (test.expectedOutput |> displayValue)
                                    , deleteButton selfIndex
                                    ]

                        columns : List (Element.IndexedColumn TestCase Msg)
                        columns =
                            let
                                maxIndex : Int
                                maxIndex =
                                    List.length inputNameList + 1

                                styles : List (Element.Attribute msg)
                                styles =
                                    [ paddingXY (model.theme |> Theme.scaled -2) (model.theme |> Theme.scaled -5), Background.color <| rgb 0.9 0.9 0.9, width fill ]
                            in
                            List.map
                                (\( columnIndex, columnName ) ->
                                    { header = ifThenElse (columnIndex == maxIndex) (el (Font.bold :: styles) <| Theme.ellipseText columnName) (el styles <| Theme.ellipseText columnName)
                                    , width = Element.shrink
                                    , view =
                                        \index test ->
                                            testRow columnIndex index maxIndex test
                                    }
                                )
                                (inputNameList ++ [ ( maxIndex, "exp. output" ) ])
                    in
                    Element.indexedTable
                        [ padding (model.theme |> Theme.scaled -2)
                        ]
                        { data = Array.toList listOfTestcases
                        , columns = columns
                        }
            in
            ifThenElse (Array.isEmpty listOfTestcases)
                none
                (column [ height fill, width fill ]
                    [ el [ Font.bold, padding (model.theme |> Theme.scaled -2), Font.underline ]
                        (text "TEST CASES")
                    , testsTable
                    ]
                )
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

                                                    inputs : List (Maybe RawValue)
                                                    inputs =
                                                        valueDef.inputTypes |> List.map (\( argName, _, _ ) -> Dict.get argName model.insightViewState.variables)

                                                    ir : IR
                                                    ir =
                                                        IR.fromDistribution distribution
                                                in
                                                Just <| tabsComponent
                                                    { theme = model.theme
                                                    , switchTab = UI << SwitchTab
                                                    , activeTab = model.activeTabIndex
                                                    , tabs = Array.fromList [ 
                                                        { name = "Insight View", content =column
                                                                [ width fill, height fill, spacing (model.theme |> Theme.scaled 8), paddingEach { left = model.theme |> Theme.scaled 2, top = 0, right = model.theme |> Theme.scaled 2, bottom = 0 } ]
                                                                [ column [ spacing (model.theme |> Theme.scaled 5) ]
                                                                    [ el [ Font.bold, Font.underline ] (text "INPUTS")
                                                                    , viewArgumentEditors ir model.argStates valueDef.inputTypes
                                                                    , ViewValue.viewDefinition (insightViewConfig ir) fullyQualifiedName valueDef
                                                                    , viewActualOutput
                                                                        model.theme
                                                                        ir
                                                                        { description = "", expectedOutput = Value.toRawValue <| Value.Tuple () [], inputs = inputs }
                                                                        fullyQualifiedName
                                                                    , ifThenElse (Dict.isEmpty model.argStates) none descriptionInput
                                                                    ]
                                                                , scenarios fullyQualifiedName ir valueDef.inputTypes
                                                                ] }, 
                                                        { name = "XRay View", content = XRayView.viewValueDefinition (XRayView.viewType <| pathToUrl) valueDef } ]
                                                    }
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


initArgumentStates : IRState -> Maybe Definition -> InsightArgumentState
initArgumentStates irState maybeSelectedDefinition =
    case irState of
        IRLoaded ((Library _ _ packageDef) as distribution) ->
            case maybeSelectedDefinition of
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
                                                    ir : IR
                                                    ir =
                                                        IR.fromDistribution distribution
                                                in
                                                Just <|
                                                    Dict.fromList
                                                        (valueDef.inputTypes
                                                            |> List.map
                                                                (\( argName, _, argType ) ->
                                                                    ( argName
                                                                    , ValueEditor.initEditorState ir argType Nothing
                                                                    )
                                                                )
                                                        )
                                            )
                                        |> Maybe.withDefault Dict.empty

                                Nothing ->
                                    Dict.empty

                        Type _ ->
                            Dict.empty

                Nothing ->
                    Dict.empty

        IRLoading ->
            Dict.empty


initInsightViewState : InsightArgumentState -> Morphir.Visual.Config.VisualState
initInsightViewState argState =
    { emptyVisualState
        | variables =
            argState
                |> Dict.map (\_ arg -> arg.lastValidValue |> Maybe.withDefault (Value.Unit ()))
    }
