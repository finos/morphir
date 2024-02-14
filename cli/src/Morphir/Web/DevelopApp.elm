port module Morphir.Web.DevelopApp exposing (IRState(..), Model, Msg(..), ServerState(..), httpMakeModel, init, main, routeParser, subscriptions, update, view, viewBody, viewHeader)

import Array exposing (Array)
import Array.Extra
import Browser
import Browser.Navigation as Nav
import Dict exposing (Dict)
import Element
    exposing
        ( Element
        , above
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
        , image
        , inFront
        , layout
        , link
        , maximum
        , mouseOver
        , none
        , padding
        , paddingEach
        , paddingXY
        , paragraph
        , pointer
        , px
        , rgb
        , rgba
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
import FontAwesome.Styles as Icon
import Http exposing (emptyBody, jsonBody)
import List.Extra
import Loading
import Morphir.Correctness.Codec exposing (decodeTestSuite, encodeTestSuite)
import Morphir.Correctness.Test exposing (TestCase, TestSuite)
import Morphir.IR.Decoration exposing (AllDecorationConfigAndData, DecorationData, DecorationID)
import Morphir.IR.Decoration.Codec exposing (decodeAllDecorationConfigAndData, decodeDecorationData, encodeDecorationData)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.FormatVersion.Codec as DistributionCodec
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.NodeId exposing (NodeID(..))
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Repo as Repo exposing (Repo)
import Morphir.IR.SDK as SDK
import Morphir.IR.Type as Type exposing (Type(..))
import Morphir.IR.Value as Value exposing (RawValue, Value(..))
import Morphir.SDK.Dict as SDKDict
import Morphir.TestCoverage.Backend exposing (getValueBranchCoverage)
import Morphir.Type.Infer as Infer
import Morphir.Value.Error exposing (Error)
import Morphir.Value.Interpreter exposing (evaluateFunctionValue)
import Morphir.Visual.Common exposing (nameToText, nameToTitleText, pathToDisplayString, pathToFullUrl, pathToTitleText, pathToUrl, tooltip)
import Morphir.Visual.Components.Card as Card
import Morphir.Visual.Components.FieldList as FieldList
import Morphir.Visual.Components.InputComponent as InputComponent
import Morphir.Visual.Components.ModalComponent exposing (attachModal)
import Morphir.Visual.Components.SectionComponent as SectionComponent
import Morphir.Visual.Components.SelectableElement as SelectableElement
import Morphir.Visual.Components.TabsComponent as TabsComponent
import Morphir.Visual.Components.TreeViewComponent as TreeViewComponent
import Morphir.Visual.Components.TypeBuilder as TypeBuilder
import Morphir.Visual.Config exposing (DrillDownFunctions(..), ExpressionTreePath, PopupScreenRecord, addToDrillDown, removeFromDrillDown)
import Morphir.Visual.EnrichedValue exposing (fromRawValue)
import Morphir.Visual.Theme as Theme exposing (Theme, borderBottom, borderRounded, largePadding, largeSpacing, smallPadding)
import Morphir.Visual.ValueEditor as ValueEditor
import Morphir.Visual.ViewType as ViewType
import Morphir.Visual.ViewValue as ViewValue
import Morphir.Visual.XRayView as XRayView
import Morphir.Web.Graph.DependencyGraph exposing (dependencyGraph)
import Ordering
import Set exposing (Set)
import Url exposing (Url)
import Url.Parser as UrlParser exposing (..)
import Url.Parser.Query as Query



-- MAIN


main : Program Flags Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlChange = Navigate << UrlChanged
        , onUrlRequest = Navigate << LinkClicked
        }


port unsavedChangesPort : Bool -> Cmd msg



-- MODEL


type alias Model =
    { key : Nav.Key
    , theme : Theme
    , irState : IRState
    , serverState : ServerState
    , testSuite : Dict FQName (Array TestCase)
    , collapsedModules : Set (TreeViewComponent.NodePath ModuleName)
    , showModules : Bool
    , showDefinitions : Bool
    , homeState : HomeState
    , repo : Repo
    , insightViewState : Morphir.Visual.Config.VisualState
    , typeBuilderState : TypeBuilder.State
    , argStates : InsightArgumentState
    , expandedValues : Dict ( FQName, Name ) (Value.Definition () (Type ()))
    , allDecorationConfigAndData : AllDecorationConfigAndData
    , decorationEditorStates : DecorationEditorStates
    , selectedTestcaseIndex : Int
    , testDescription : String
    , activeTabIndex : Int
    , openSections : Set Int
    , isModalOpen : Bool
    , modalContent : Element Msg
    , version : String
    , showSaveTestError : Bool
    , unsavedChanges : Bool
    }


type alias Flags =
    { version : String
    }


type alias InsightArgumentState =
    Dict Name ValueEditor.EditorState


type alias DecorationEditorStates =
    SDKDict.Dict DecorationNodeID ValueEditor.EditorState


type alias HomeState =
    { selectedPackage : Maybe PackageName
    , selectedModule : Maybe ( TreeViewComponent.NodePath ModuleName, ModuleName )
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
    | IRReloading Distribution
    | IRLoaded Distribution


type ServerState
    = ServerOk
    | ServerError String Http.Error
    | ServerWarning String Http.Error


init : Flags -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    let
        initModel =
            { key = key
            , theme = Theme.fromConfig Nothing
            , irState = IRLoading
            , serverState = ServerOk
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
            , typeBuilderState = TypeBuilder.init Nothing False
            , argStates = Dict.empty
            , expandedValues = Dict.empty
            , allDecorationConfigAndData = Dict.empty
            , decorationEditorStates = SDKDict.empty
            , selectedTestcaseIndex = -1
            , testDescription = ""
            , activeTabIndex = 0
            , openSections = Set.fromList [ 1 ]
            , isModalOpen = False
            , modalContent = none
            , version = flags.version
            , showSaveTestError = False
            , unsavedChanges = False
            }
    in
    ( toRoute url initModel
    , Cmd.batch [ httpMakeModel, httpAttributes ]
    )


emptyVisualState : Morphir.Visual.Config.VisualState
emptyVisualState =
    { theme = Theme.fromConfig Nothing
    , variables = Dict.empty
    , nonEvaluatedVariables = Dict.empty
    , highlightState = Nothing
    , popupVariables =
        { variableIndex = 0
        , variableValue = Nothing
        , nodePath = []
        }
    , drillDownFunctions = DrillDownFunctions Dict.empty
    , zIndex = 9999
    }



-- UPDATE


type Msg
    = Navigate NavigationMsg
    | HttpError String Http.Error
    | HttpWarning String Http.Error
    | ServerGetIRResponse Distribution
    | ServerGetTestsResponse TestSuite
    | ServerGetAllDecorationConfigAndDataResponse AllDecorationConfigAndData
    | ServerGetDecorationDataResponse DecorationID DecorationData
    | Filter FilterMsg
    | UI UIMsg
    | Insight InsightMsg
    | Testing TestingMsg
    | Decoration DecorationMsg
    | DoNothing


type DecorationMsg
    = DecorationValueUpdated DecorationNodeID ValueEditor.EditorState


type alias DecorationNodeID =
    { decorationID : DecorationID
    , nodeID : NodeID
    }


type TestingMsg
    = DeleteTestCase FQName Int
    | SaveTestSuite FQName TestCase
    | LoadTestCase (List ( Name, Type () )) (List (Maybe RawValue)) String Int
    | UpdateTestCase FQName TestCase
    | UpdateDescription String
    | ShowSaveTestError


type NavigationMsg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | DefinitionSelected String


type UIMsg
    = ToggleModulesMenu
    | ToggleDefinitionsMenu
    | ExpandModule (TreeViewComponent.NodePath ModuleName)
    | CollapseModule (TreeViewComponent.NodePath ModuleName)
    | SwitchTab Int
    | ToggleSection Int
    | OpenAbout
    | OpenHttpErrorModal Http.Error String Bool
    | DismissHttpError
    | CloseModal
    | TypeBuilderChanged TypeBuilder.State
    | TypeAdded TypeBuilder.NewType
    | SaveIR


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

        resetTabs : Model -> Model
        resetTabs m =
            { m | activeTabIndex = 0 }

        toStoredTestSuite : Dict FQName (Array TestCase) -> Dict FQName (List TestCase)
        toStoredTestSuite testSuite =
            Dict.fromList
                (List.map
                    (\( k, v ) ->
                        ( k
                        , Array.toList v
                            -- the interpreter and insightViewState needs Unit in places where no input is given, but we can't encode a value that does not match the parameter type
                            |> List.map
                                (\testCase ->
                                    { testCase
                                        | inputs =
                                            List.map
                                                (\i ->
                                                    if i == Just (Value.Unit ()) then
                                                        Nothing

                                                    else
                                                        i
                                                )
                                                testCase.inputs
                                    }
                                )
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
                            ( resetTabs model, Nav.pushUrl model.key (Url.toString url) )

                        Browser.External href ->
                            ( resetTabs model, Nav.load href )

                UrlChanged url ->
                    ( model |> resetTabs |> toRoute url, Cmd.none )

                DefinitionSelected url ->
                    ( resetTabs model, Nav.pushUrl model.key url )

        HttpError errorSummary httpError ->
            ( { model | serverState = ServerError errorSummary httpError }
            , Cmd.none
            )

        HttpWarning errorSummary httpError ->
            ( { model | serverState = ServerWarning errorSummary httpError }
            , Cmd.none
            )

        ServerGetIRResponse (Library packageName dependencies packageDef) ->
            let
                distribution =
                    Library packageName (dependencies |> Dict.insert SDK.packageName SDK.packageSpec) packageDef

                irLoaded : IRState
                irLoaded =
                    IRLoaded distribution

                initialArgumentStates : InsightArgumentState
                initialArgumentStates =
                    initArgumentStates irLoaded model.homeState.selectedDefinition
            in
            case Repo.fromDistribution distribution of
                Ok r ->
                    ( { model | irState = irLoaded, repo = r, argStates = initialArgumentStates, insightViewState = initInsightViewState initialArgumentStates, unsavedChanges = False }
                    , Cmd.batch [ httpTestModel distribution, unsavedChangesPort False ]
                    )

                Err _ ->
                    ( { model
                        | irState = irLoaded
                        , serverState =
                            ServerError "Could not transform Distribution to Repo" (Http.BadBody "Could not transform Distribution to Repo")
                      }
                    , httpTestModel distribution
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
                        , showDefinitions =
                            if not model.showModules then
                                True

                            else
                                model.showDefinitions
                      }
                    , Cmd.none
                    )

                ToggleDefinitionsMenu ->
                    ( { model
                        | showDefinitions = not model.showDefinitions
                        , showModules =
                            if not model.showDefinitions then
                                model.showDefinitions

                            else
                                False
                      }
                    , Cmd.none
                    )

                SwitchTab tabIndex ->
                    ( { model | activeTabIndex = tabIndex }, Cmd.none )

                ToggleSection sectionId ->
                    if Set.member sectionId model.openSections then
                        ( { model | openSections = Set.remove sectionId model.openSections }, Cmd.none )

                    else
                        ( { model | openSections = Set.insert sectionId model.openSections }, Cmd.none )

                OpenAbout ->
                    ( { model | isModalOpen = True, modalContent = viewAbout model.theme model.version }, Cmd.none )

                OpenHttpErrorModal error errorSummary isWarning ->
                    ( { model | isModalOpen = True, serverState = ServerOk, modalContent = serverErrorModal model.theme error errorSummary isWarning }, Cmd.none )

                DismissHttpError ->
                    let
                        newModel : Model
                        newModel =
                            { model | serverState = ServerOk }
                    in
                    ( newModel, Cmd.none )

                CloseModal ->
                    ( { model | isModalOpen = False }, Cmd.none )

                TypeBuilderChanged newTypeBuilderState ->
                    ( { model | typeBuilderState = newTypeBuilderState }, Cmd.none )

                TypeAdded newType ->
                    case model.repo |> Repo.insertType newType.moduleName newType.name newType.definition newType.access newType.documentation of
                        Ok newRepo ->
                            ( { model | typeBuilderState = TypeBuilder.init (model.homeState.selectedModule |> Maybe.map Tuple.second) True, unsavedChanges = True, irState = IRLoaded (Repo.toDistribution newRepo), repo = newRepo }
                            , unsavedChangesPort True
                            )

                        _ ->
                            ( model, Cmd.none )

                SaveIR ->
                    ( { model | irState = IRReloading (Repo.toDistribution model.repo) }, httpSaveDistribution (Repo.toDistribution model.repo) )

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
                    ( resetTabs model
                    , Nav.replaceUrl model.key (filterStateToQueryParams { filterState | moduleClicked = path, searchText = "" })
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
                    ( { model | testSuite = newTestSuite, selectedTestcaseIndex = -1, testDescription = "", argStates = initalArgState, insightViewState = initInsightViewState initalArgState, showSaveTestError = False }
                    , httpSaveTestSuite getDistribution (toStoredTestSuite newTestSuite) (toStoredTestSuite model.testSuite)
                    )

                DeleteTestCase fQName index ->
                    let
                        newTestSuite : Dict FQName (Array TestCase)
                        newTestSuite =
                            Dict.insert fQName
                                (Array.Extra.removeAt index (Dict.get fQName model.testSuite |> Maybe.withDefault Array.empty))
                                model.testSuite
                    in
                    ( { model
                        | testSuite = newTestSuite
                        , selectedTestcaseIndex =
                            if model.selectedTestcaseIndex == index then
                                -1

                            else
                                model.selectedTestcaseIndex
                      }
                    , httpSaveTestSuite getDistribution (toStoredTestSuite newTestSuite) (toStoredTestSuite model.testSuite)
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
                            ValueEditor.initEditorState getDistribution tpe val

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
                        , showSaveTestError = False
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
                    ( { model | testSuite = newTestSuite, selectedTestcaseIndex = -1, testDescription = "", argStates = initalArgState, insightViewState = initInsightViewState initalArgState, showSaveTestError = False }
                    , httpSaveTestSuite getDistribution (toStoredTestSuite newTestSuite) (toStoredTestSuite model.testSuite)
                    )

                ShowSaveTestError ->
                    ( { model | showSaveTestError = True }, Cmd.none )

        ServerGetAllDecorationConfigAndDataResponse decorations ->
            ( { model | allDecorationConfigAndData = decorations }
            , Cmd.none
            )

        ServerGetDecorationDataResponse decorationID decorationData ->
            ( { model
                | allDecorationConfigAndData =
                    model.allDecorationConfigAndData
                        |> Dict.update decorationID
                            (\maybeExistingDecorationConfigAndData ->
                                maybeExistingDecorationConfigAndData
                                    |> Maybe.map
                                        (\existingDecorationConfigAndData ->
                                            { existingDecorationConfigAndData
                                                | data = decorationData
                                            }
                                        )
                            )
              }
            , Cmd.none
            )

        Decoration decorationMsg ->
            case decorationMsg of
                DecorationValueUpdated valueDetail editorState ->
                    let
                        updatedEditorStates : DecorationEditorStates
                        updatedEditorStates =
                            model.decorationEditorStates
                                |> SDKDict.insert valueDetail editorState

                        updatedDecorationsConfigAndData : AllDecorationConfigAndData
                        updatedDecorationsConfigAndData =
                            model.allDecorationConfigAndData
                                |> Dict.update valueDetail.decorationID
                                    (Maybe.map
                                        (\decorationConfigAndData ->
                                            let
                                                irValueUpdate : SDKDict.Dict NodeID (Value () ()) -> SDKDict.Dict NodeID (Value () ())
                                                irValueUpdate data =
                                                    case editorState.lastValidValue of
                                                        Just validValue ->
                                                            data
                                                                |> SDKDict.insert valueDetail.nodeID validValue

                                                        Nothing ->
                                                            data
                                                                |> SDKDict.remove valueDetail.nodeID
                                            in
                                            { decorationConfigAndData
                                                | data =
                                                    decorationConfigAndData.data
                                                        |> irValueUpdate
                                            }
                                        )
                                    )
                    in
                    case editorState.errorState of
                        Just _ ->
                            -- when the editor is in an invalid state we don't need to update the decoration data but
                            -- we still need to update the editor states
                            ( { model
                                | decorationEditorStates = updatedEditorStates
                              }
                            , Cmd.none
                            )

                        Nothing ->
                            ( { model
                                | allDecorationConfigAndData = updatedDecorationsConfigAndData
                                , decorationEditorStates = updatedEditorStates
                              }
                            , httpSaveAttrValue valueDetail.decorationID updatedDecorationsConfigAndData
                            )

        DoNothing ->
            ( model, Cmd.none )



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
            { model
                | homeState = newState
                , insightViewState = initInsightViewState initialArgState
                , argStates = initialArgState
                , selectedTestcaseIndex = -1
                , testDescription = ""
                , openSections = Set.fromList [ 1 ]
                , typeBuilderState = TypeBuilder.init (newState.selectedModule |> Maybe.map Tuple.second) model.unsavedChanges
            }

        -- When selecting a definition, we should not change the selected module, once the user explicitly selected one
        keepOrChangeSelectedModule : ( List Path, ModuleName )
        keepOrChangeSelectedModule =
            if filterState.moduleClicked == pack then
                ( urlFragmentToNodePath "", [] )

            else if filterState.moduleClicked == "" then
                ( urlFragmentToNodePath mod, Path.fromString mod )

            else
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
            if filterState.searchText == "" then
                ""

            else
                "&search=" ++ filterState.searchText

        filterValues : String
        filterValues =
            if filterState.showValues then
                ""

            else
                "&showValues=false"

        filterTypes : String
        filterTypes =
            if filterState.showTypes then
                ""

            else
                "&showTypes=false"

        moduleClicked =
            if filterState.moduleClicked == "" then
                ""

            else
                "&moduleClicked=" ++ filterState.moduleClicked
    in
    "?" ++ search ++ filterValues ++ filterTypes ++ moduleClicked



-- VIEW


{-| Top level function to render the current ui state
-}
view : Model -> Browser.Document Msg
view model =
    { title = "Morphir - Home"
    , body =
        [ Icon.css
        , layout
            [ Font.family
                [ Font.external
                    { name = "Poppins"
                    , url = "https://fonts.googleapis.com/css2?family=Poppins:wght@400&display=swap"
                    }
                , Font.sansSerif
                ]
            , Font.size model.theme.fontSize
            , width fill
            , height fill
            , attachModal model.theme
                { content = model.modalContent
                , isOpen = model.isModalOpen
                , onClose = UI CloseModal
                }
            ]
            (column
                [ width fill
                , height fill
                ]
                [ viewHeader model
                , el
                    [ width fill
                    , height fill
                    ]
                    (viewBody model)
                , serverErrorBar model.theme model.serverState
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
        , Background.color model.theme.colors.brandPrimary
        ]
        [ row
            [ width fill, paddingEach { top = 0, left = 0, bottom = 0, right = largeSpacing model.theme } ]
            [ link []
                { url = "/home" ++ filterStateToQueryParams model.homeState.filterState
                , label =
                    row
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
                }
            , el
                [ alignRight
                , Font.color model.theme.colors.lightest
                , Font.size (Theme.scaled 5 model.theme)
                ]
              <|
                if model.unsavedChanges then
                    text " You have unsaved changes! "

                else
                    Element.none
            , el
                [ alignRight
                , pointer
                , Theme.borderBottom 1
                , Border.color model.theme.colors.brandPrimary
                , mouseOver [ Border.color model.theme.colors.lightest ]
                , onClick (UI OpenAbout)
                , Font.color model.theme.colors.lightest
                , Font.size (Theme.scaled 5 model.theme)
                ]
              <|
                text " ⓘ "
            ]
        ]


{-| Display server errors on the UI
-}
serverErrorBar : Theme -> ServerState -> Element Msg
serverErrorBar theme serverState =
    let
        clickable : msg -> Element.Color -> Element.Color -> String -> Element msg
        clickable msg textColor borderColor label =
            Element.Input.button
                [ pointer
                , Font.color textColor
                , Theme.borderBottom 1
                , Border.color borderColor
                , mouseOver [ Border.color textColor ]
                ]
                { onPress = Just <| msg, label = text label }

        barStyles : List (Element.Attribute msg)
        barStyles =
            [ width fill
            , padding (largePadding theme)
            , Font.size (Theme.scaled 3 theme)
            , spacing (Theme.largeSpacing theme)
            , height <| px 40
            , clipY
            ]
    in
    case serverState of
        ServerOk ->
            none

        ServerError errorSummary error ->
            row
                ([ Background.color theme.colors.negativeLight
                 , Font.color theme.colors.lightest
                 ]
                    ++ barStyles
                )
                [ el [ width fill ] (text errorSummary)
                , clickable (UI <| OpenHttpErrorModal error errorSummary False) theme.colors.lightest theme.colors.negativeLight "See details"
                , clickable (UI DismissHttpError) theme.colors.lightest theme.colors.negativeLight " X "
                ]

        ServerWarning errorSummary error ->
            row
                ([ Background.color theme.colors.backgroundColor
                 , Font.color theme.colors.darkest
                 ]
                    ++ barStyles
                )
                [ el [ width fill ] (text errorSummary)
                , clickable (UI <| OpenHttpErrorModal error errorSummary True) theme.colors.darkest theme.colors.warning "See details"
                , clickable (UI DismissHttpError) theme.colors.darkest theme.colors.warning " X "
                ]


serverErrorModal : Theme -> Http.Error -> String -> Bool -> Element Msg
serverErrorModal theme error errorSummary isWarning =
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
    column
        [ borderRounded theme
        , spacing (Theme.mediumSpacing theme)
        , width fill
        , height fill
        , padding (largePadding theme)
        , Background.color theme.colors.lightest
        ]
        [ row [ width fill, Font.size (Theme.scaled 5 theme) ]
            [ el
                [ if isWarning then
                    Font.color theme.colors.warning

                  else
                    Font.color theme.colors.negativeLight
                , Font.bold
                ]
                (text <|
                    if isWarning then
                        "Warning"

                    else
                        "Error"
                )
            , el
                [ alignRight
                , alignTop
                , onClick (UI CloseModal)
                , pointer
                , Background.color theme.colors.lightest
                , Font.color theme.colors.darkest
                , borderRounded theme
                , Font.bold
                ]
                (text " x ")
            ]
        , row [ width fill ] [ text <| errorSummary ++ ":" ]
        , row
            [ clipY
            , width fill
            , Border.width 2
            , padding (smallPadding theme)
            , borderRounded theme
            , height (px 250)
            ]
            [ el [ width fill, height fill, scrollbars, padding (smallPadding theme) ] (text message) ]
        ]


{-| Display the main part of home UI if the IR has loaded
-}
viewBody : Model -> Element Msg
viewBody model =
    case model.irState of
        IRLoading ->
            el
                [ width fill
                , height fill
                , Background.color model.theme.colors.gray
                ]
                (el
                    [ padding (Theme.scaled 5 model.theme)
                    , Font.size (Theme.scaled 5 model.theme)
                    ]
                    (text "Loading the IR ...")
                )

        IRReloading (Library packageName _ packageDef) ->
            el
                [ width fill
                , height fill
                , centerX
                , centerY
                , inFront <|
                    el [ Background.color model.theme.colors.lightGray, onClick DoNothing, width fill, height fill ] <|
                        el [ centerX, centerY ] <|
                            Element.html (Loading.render Loading.Circle Loading.defaultConfig Loading.On)
                ]
                (viewHome model packageName packageDef)

        IRLoaded (Library packageName _ packageDef) ->
            viewHome model packageName packageDef


listStyles : Theme -> List (Element.Attribute msg)
listStyles theme =
    [ width fill
    , Background.color theme.colors.lightest
    , theme |> Theme.borderRounded
    , paddingXY (theme |> Theme.scaled 3) (theme |> Theme.scaled -1)
    ]


viewAbout : Theme -> String -> Element Msg
viewAbout theme version =
    let
        about : Element msg
        about =
            row [ width fill, padding (largePadding theme) ] [ paragraph [] [ text "On this page you can browse through the types and definitions of a MorphIR package, and see how they behave and interact.", text "Select a definition on the left to begin. " ] ]

        feedback : Element msg
        feedback =
            let
                gitHubLink =
                    link [] { url = "https://github.com/finos/morphir-elm/issues", label = el [ Font.color theme.colors.brandPrimary ] (text "GitHub issues page.") }
            in
            row [ width fill, padding (largePadding theme) ] [ text "If you would like to report a bug, or to provide feedback, please visit our ", gitHubLink ]

        close : Element Msg
        close =
            el [ alignRight, onClick (UI CloseModal), pointer ] (text " x ")

        sectionTitleStyles : List (Element.Attribute msg)
        sectionTitleStyles =
            [ width fill, Font.size (Theme.scaled 5 theme), Font.bold ]
    in
    column [ width fill, height fill, padding (largePadding theme), spacing (largeSpacing theme), Background.color theme.colors.lightest, Border.color theme.colors.lightest, borderRounded theme ]
        [ row sectionTitleStyles [ text "About", close ]
        , about
        , row sectionTitleStyles [ text "Feedback" ]
        , feedback
        , row sectionTitleStyles [ text "Version" ]
        , row [ width fill, padding (largePadding theme) ] [ text <| "This page is currently running version " ++ version ]
        ]


{-| View to display the ValueEditors for Decorations when a node is selected
-}
viewDecorationValues : Model -> NodeID -> Element Msg
viewDecorationValues model node =
    let
        attributeToEditors : Element Msg
        attributeToEditors =
            model.allDecorationConfigAndData
                |> Dict.toList
                |> List.map
                    (\( attrId, attrDetail ) ->
                        let
                            irValue : Maybe (Value () ())
                            irValue =
                                attrDetail.data
                                    |> SDKDict.get node

                            nodeDetail : DecorationNodeID
                            nodeDetail =
                                { decorationID = attrId, nodeID = node }

                            editorState : ValueEditor.EditorState
                            editorState =
                                model.decorationEditorStates
                                    |> SDKDict.get nodeDetail
                                    |> Maybe.withDefault
                                        (ValueEditor.initEditorState
                                            attrDetail.iR
                                            (Type.Reference () attrDetail.entryPoint [])
                                            irValue
                                        )
                        in
                        ( Name.fromString attrDetail.displayName
                        , ValueEditor.view
                            model.theme
                            attrDetail.iR
                            (Type.Reference () attrDetail.entryPoint [])
                            (Decoration << DecorationValueUpdated nodeDetail)
                            editorState
                        )
                    )
                |> FieldList.view model.theme
    in
    column [ spacing (model.theme |> Theme.scaled 5) ]
        [ attributeToEditors ]


{-| Display the home UI
-}
viewHome : Model -> PackageName -> Package.Definition () (Type ()) -> Element Msg
viewHome model packageName packageDef =
    let
        -- A document tree like view of the modules in the current package
        moduleTree : Element Msg
        moduleTree =
            el
                (listStyles model.theme ++ [ height fill, scrollbars ])
                (TreeViewComponent.view model.theme
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

        maybeModuleName : Maybe ModuleName
        maybeModuleName =
            model.homeState.selectedModule |> Maybe.map Tuple.second

        entryPoints : List FQName
        entryPoints =
            maybeModuleName |> Maybe.map (Repo.findModuleEntryPoints model.repo) |> Maybe.withDefault []

        -- Creates three tabs showing a summary, a dep. graph and decorators which are shown when no definition is selected
        homeTabs : Element Msg
        homeTabs =
            let
                col : List (Element msg) -> Element msg
                col elements =
                    column
                        [ height fill
                        , width fill
                        , scrollbars
                        ]
                        elements

                summary : Element Msg
                summary =
                    let
                        displayModuleName : ModuleName -> Element msg
                        displayModuleName mn =
                            mn
                                |> List.Extra.last
                                >> Maybe.withDefault []
                                |> (Name.toHumanWords >> String.join " ")
                                |> (\name -> text <| ("Entrypoints of  " ++ name ++ " :"))
                                |> el [ Font.bold, padding <| Theme.smallPadding model.theme ]

                        displayEntryPoints : Element Msg
                        displayEntryPoints =
                            entryPoints
                                |> List.map (\( _, moduleName, localName ) -> entrypointEl moduleName localName)
                                |> column [ spacing (Theme.smallSpacing model.theme), paddingXY (Theme.smallPadding model.theme) 0 ]

                        linkToDefinition : ModuleName -> Name -> String
                        linkToDefinition moduleName name =
                            pathToFullUrl [ packageName, moduleName ] ++ "/" ++ Name.toCamelCase name ++ filterStateToQueryParams model.homeState.filterState

                        entrypointEl : ModuleName -> Name -> Element Msg
                        entrypointEl moduleName localName =
                            let
                                modulePathName : String
                                modulePathName =
                                    String.append
                                        ((maybeModuleName
                                            |> Maybe.map
                                                (List.foldl List.Extra.remove moduleName
                                                    >> List.intersperse [ " : " ]
                                                    >> List.map Name.toTitleCase
                                                    >> String.concat
                                                )
                                         )
                                            |> Maybe.withDefault ""
                                        )
                                        " : "
                            in
                            SelectableElement.view model.theme
                                { isSelected = False
                                , content = text <| (" > " ++ modulePathName ++ (Name.toHumanWords >> String.join " ") localName)
                                , onSelect = Navigate (DefinitionSelected (linkToDefinition moduleName localName))
                                }
                    in
                    case model.homeState.selectedModule of
                        Just ( _, moduleName ) ->
                            column [ spacing (Theme.smallSpacing model.theme), padding (Theme.smallPadding model.theme), height fill, width fill, scrollbars ]
                                [ displayModuleName moduleName, displayEntryPoints ]

                        Nothing ->
                            row [ width fill, spacing (Theme.smallSpacing model.theme), padding (Theme.smallPadding model.theme) ] []
            in
            TabsComponent.view model.theme
                { onSwitchTab = UI << SwitchTab
                , activeTab = model.activeTabIndex
                , tabs =
                    Array.fromList
                        ([ { name = "Summary"
                           , content = \_ -> col [ summary ]
                           }
                         , { name = "Dependency Graph"
                           , content = \_ -> col [ dependencyGraph model.homeState.selectedModule model.repo ]
                           }
                         ]
                            ++ (case maybeModuleName of
                                    Just moduleName ->
                                        [ { name = "Decorations"
                                          , content =
                                                \_ -> col [ viewDecorationValues model (ModuleID ( packageName, moduleName )) ]
                                          }
                                        , { name = "Add new term"
                                          , content =
                                                \_ ->
                                                    col <|
                                                        [ TypeBuilder.view model.theme
                                                            { state = model.typeBuilderState, onStateChange = UI << TypeBuilderChanged, onTypeAdd = UI << TypeAdded, onIRSave = UI SaveIR }
                                                            packageName
                                                            packageDef
                                                            moduleName
                                                        ]
                                          }
                                        ]

                                    Nothing ->
                                        []
                               )
                        )
                }
    in
    row [ width fill, height fill, Background.color model.theme.colors.gray, spacing (Theme.smallSpacing model.theme) ]
        [ column
            [ width (fillPortion 1)
            , height fill
            , scrollbars
            ]
            [ column [ width fill, height fill, scrollbars, spacing (Theme.smallSpacing model.theme) ]
                [ if model.showModules then
                    moduleTree

                  else
                    none
                , if model.showDefinitions then
                    definitionList packageName packageDef model entryPoints

                  else
                    none
                ]
            ]
        , column
            [ height fill
            , width (fillPortion 4)
            , Background.color model.theme.colors.lightest
            , scrollbars
            ]
            [ if model.homeState.selectedDefinition == Nothing then
                homeTabs

              else
                column
                    [ scrollbars, height (fillPortion 2), paddingEach { bottom = 3, top = model.theme |> Theme.scaled 1, left = model.theme |> Theme.scaled 1, right = 0 }, width fill, spacing (model.theme |> Theme.scaled 1) ]
                    [ viewDefinition packageDef model.theme model.homeState.selectedDefinition
                    , el [ height fill, width fill, scrollbars ]
                        (viewDefinitionDetails model)
                    ]
            ]
        ]


definitionList : PackageName -> Package.Definition () (Type ()) -> Model -> List FQName -> Element Msg
definitionList packageName packageDef model entrypoints =
    let
        -- Given a module name and a module definition, returns a list of tuples with the module's definitions, and their human readable form
        moduleDefinitionsAsUiElements : ModuleName -> Module.Definition () (Type ()) -> List ( Definition, Element Msg )
        moduleDefinitionsAsUiElements moduleName moduleDef =
            let
                definitionUiElement : Element Msg -> Definition -> Name -> (Name -> String) -> Element Msg
                definitionUiElement icon definition name nameTransformation =
                    let
                        elem : Element Msg
                        elem =
                            row
                                [ width fill
                                , paddingXY 0 (Theme.smallPadding model.theme)
                                ]
                                [ el [ width <| fillPortion 1, alignLeft ] icon
                                , el
                                    [ width <| fillPortion 8
                                    , clipX
                                    , alignLeft
                                    ]
                                    (Theme.ellipseText (" " ++ nameToText name))
                                , el
                                    [ alignRight
                                    , Font.color model.theme.colors.secondaryInformation
                                    , width <| fillPortion 5
                                    , clipX
                                    ]
                                    (Theme.ellipseText (pathToDisplayString moduleName))
                                ]
                    in
                    SelectableElement.view model.theme
                        { isSelected = model.homeState.selectedDefinition == Just definition
                        , content = elem
                        , onSelect = Navigate (DefinitionSelected (linkToDefinition name nameTransformation))
                        }

                linkToDefinition : Name -> (Name -> String) -> String
                linkToDefinition name nameTransformation =
                    pathToFullUrl [ packageName, moduleName ] ++ "/" ++ nameTransformation name ++ filterStateToQueryParams model.homeState.filterState

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
                                , definitionUiElement
                                    (Element.Keyed.el [ Font.color model.theme.colors.brandPrimary ]
                                        ( createElementKey moduleName typeName, text "ⓣ" )
                                    )
                                    (Type ( moduleName, typeName ))
                                    typeName
                                    Name.toTitleCase
                                )
                            )

                values : List ( Definition, Element Msg )
                values =
                    let
                        entryPointIndicator : Name -> Element msg
                        entryPointIndicator valueName =
                            row [ width fill ]
                                [ el [ Font.bold ] <|
                                    text <|
                                        if entrypoints |> List.any (\( _, _, v ) -> v == valueName) then
                                            "ⓔ "

                                        else
                                            ""
                                , text "ⓥ"
                                ]
                    in
                    moduleDef.values
                        |> Dict.toList
                        |> List.map
                            (\( valueName, _ ) ->
                                ( Value ( moduleName, valueName )
                                , definitionUiElement
                                    (Element.Keyed.el [ Font.color model.theme.colors.brandSecondary ]
                                        ( createElementKey moduleName valueName, entryPointIndicator valueName )
                                    )
                                    (Value ( moduleName, valueName ))
                                    valueName
                                    Name.toCamelCase
                                )
                            )
            in
            (if model.homeState.filterState.showValues then
                values

             else
                []
            )
                ++ (if model.homeState.filterState.showTypes then
                        types

                    else
                        []
                   )

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
                            [ text "Please select a module above!" ]

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

        -- A path to the currently selected module in an easily readable format
        pathToSelectedModule : List (Element Msg)
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
    in
    column
        [ Background.color model.theme.colors.gray
        , height fill
        , width
            (if model.showModules then
                fillPortion 3

             else
                fill
            )
        , spacing (model.theme |> Theme.scaled -2)
        , clipX
        ]
        [ definitionFilters model.theme model.homeState
        , row [ width fill, height <| fillPortion 1, Font.bold, paddingXY 5 0 ]
            pathToSelectedModule
        , Element.Keyed.row ([ width fill, height <| fillPortion 23, scrollbars ] ++ listStyles model.theme) [ ( "definitions", viewDefinitionLabels (model.homeState.selectedModule |> Maybe.map Tuple.second) ) ]
        ]



{-
   Creates UI elements to filter definitions by name, and type/value
-}


definitionFilters : Theme -> HomeState -> Element Msg
definitionFilters theme homeState =
    let
        -- Creates a text input to search defintions by name
        definitionFilter : Element Msg
        definitionFilter =
            InputComponent.searchInput
                theme
                [ padding (theme |> Theme.scaled -2)
                , width (fillPortion 7)
                ]
                { onChange = Filter << SearchDefinition
                , text = homeState.filterState.searchText
                , placeholder = Just (Element.Input.placeholder [] (text "Search for a definition"))
                , label = Element.Input.labelHidden "Search"
                }

        -- Creates a checkbox to filter out values from the definition list
        valueCheckbox : Element Msg
        valueCheckbox =
            InputComponent.checkBox
                theme
                [ width (fillPortion 2) ]
                { onChange = Filter << ToggleValues
                , checked = homeState.filterState.showValues
                , label = Element.Input.labelLeft [] (text "values:")
                }

        -- Creates a checkbox to filter out types from the definition list
        typeCheckbox : Element Msg
        typeCheckbox =
            InputComponent.checkBox
                theme
                [ width (fillPortion 2) ]
                { onChange = Filter << ToggleTypes
                , checked = homeState.filterState.showTypes
                , label = Element.Input.labelLeft [] (text "types:")
                }
    in
    row
        [ width fill
        , spacing (theme |> Theme.scaled 1)
        , height <| fillPortion 2
        ]
        [ definitionFilter, row [ alignRight, spacing (theme |> Theme.scaled 1) ] [ valueCheckbox, typeCheckbox ] ]



{-
   Display a single selected definition on the ui
-}


viewDefinition : Package.Definition () (Type ()) -> Theme -> Maybe Definition -> Element Msg
viewDefinition packageDef theme maybeSelectedDefinition =
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
                                                [ viewValue theme moduleName valueName valueDef.value.value valueDef.value.doc
                                                ]
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
                                            ViewType.viewType theme typeName typeDef.value.value typeDef.value.doc
                                        )
                            )
                        |> Maybe.withDefault none

        Nothing ->
            text "Please select a definition on the left!"


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
                    el [ Font.extraBold, Font.size 30 ] (text (nameToText valueName))
                }

        isData : Bool
        isData =
            List.isEmpty valueDef.inputTypes
    in
    Card.viewAsCard theme
        cardTitle
        (if isData then
            "value"

         else
            "calculation"
        )
        (if docs == "" then
            "[ This definition has no associated documentation. ]"

         else
            docs
        )
        none



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
                            HttpError "We encountered an issue while loading the IR" httpError

                        Ok result ->
                            ServerGetIRResponse result
                )
                DistributionCodec.decodeVersionedDistribution
        }


httpTestModel : Distribution -> Cmd Msg
httpTestModel ir =
    Http.get
        { url = "/server/morphir-tests.json"
        , expect =
            Http.expectJson
                (\response ->
                    case response of
                        Err httpError ->
                            HttpWarning "We encountered an issue while loading the test cases" httpError

                        Ok result ->
                            ServerGetTestsResponse result
                )
                (decodeTestSuite ir)
        }


httpAttributes : Cmd Msg
httpAttributes =
    Http.get
        { url = "/server/decorations"
        , expect =
            Http.expectJson
                (\response ->
                    case response of
                        Err httpError ->
                            HttpWarning "We encountered an issue while loading Decorations" httpError

                        Ok result ->
                            ServerGetAllDecorationConfigAndDataResponse result
                )
                decodeAllDecorationConfigAndData
        }


httpSaveAttrValue : DecorationID -> AllDecorationConfigAndData -> Cmd Msg
httpSaveAttrValue decorationID allDecorationConfigAndData =
    case allDecorationConfigAndData |> Dict.get decorationID of
        Just decorationConfigAndData ->
            Http.post
                { url = "/server/update-decoration/" ++ decorationID
                , body = jsonBody (encodeDecorationData decorationConfigAndData.iR decorationConfigAndData.entryPoint decorationConfigAndData.data)
                , expect =
                    Http.expectJson
                        (\response ->
                            case response of
                                Err httpError ->
                                    HttpWarning "We encountered an issue while saving Decorations" httpError

                                Ok result ->
                                    ServerGetDecorationDataResponse decorationID result
                        )
                        (decodeDecorationData decorationConfigAndData.iR decorationConfigAndData.entryPoint)
                }

        Nothing ->
            Cmd.none


httpSaveTestSuite : Distribution -> TestSuite -> TestSuite -> Cmd Msg
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
                            HttpWarning "There was inssue saving test cases" httpError

                        Ok result ->
                            ServerGetTestsResponse result
                )
                (decodeTestSuite ir)
        }


httpSaveDistribution : Distribution -> Cmd Msg
httpSaveDistribution distribution =
    Http.post
        { url = "/server/morphir-ir.json"
        , body = jsonBody <| DistributionCodec.encodeVersionedDistribution distribution
        , expect =
            Http.expectJson
                (\response ->
                    case response of
                        Err httpError ->
                            HttpError "We encountered an issue while saving the IR" httpError

                        Ok result ->
                            ServerGetIRResponse result
                )
                DistributionCodec.decodeVersionedDistribution
        }


{-| Display a Tree View of clickable module names in the given package, with urls pointing to the give module
-}
viewModuleNames : Model -> PackageName -> ModuleName -> List ModuleName -> TreeViewComponent.Node ModuleName Msg
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
    TreeViewComponent.Node
        (\_ ->
            case currentModuleName of
                Just name ->
                    link [ pointer, onClick (handleModuleClick parentModule) ]
                        { label = text (name |> nameToTitleText)
                        , url = pathToFullUrl [ packageName, parentModule ] ++ filterStateToQueryParams model.homeState.filterState
                        }

                Nothing ->
                    link [ pointer, onClick (handleModuleClick packageName) ] { label = text (pathToTitleText packageName), url = pathToFullUrl [ packageName ] ++ filterStateToQueryParams model.homeState.filterState }
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
        insightViewConfig : Distribution -> Morphir.Visual.Config.Config Msg
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

        viewArgumentEditors : Distribution -> InsightArgumentState -> List ( Name, a, Type () ) -> Element Msg
        viewArgumentEditors ir argState inputTypes =
            inputTypes
                |> List.map
                    (\( argName, _, argType ) ->
                        ( argName
                        , ValueEditor.view model.theme
                            ir
                            argType
                            (Insight << ArgValueUpdated argName)
                            (argState |> Dict.get argName |> Maybe.withDefault (ValueEditor.initEditorState ir argType Nothing))
                        )
                    )
                |> FieldList.view model.theme

        buttonStyles : List (Element.Attribute msg)
        buttonStyles =
            [ padding 7
            , model.theme |> Theme.borderRounded
            , Background.color model.theme.colors.darkest
            , Font.color model.theme.colors.lightest
            , Font.bold
            , Font.size model.theme.fontSize
            ]

        saveTestCaseButton : FQName -> Maybe TestCase -> Element Msg
        saveTestCaseButton fqName testCase =
            let
                message : Msg
                message =
                    Testing
                        (case testCase of
                            Just tc ->
                                SaveTestSuite fqName tc

                            Nothing ->
                                ShowSaveTestError
                        )
            in
            Element.Input.button
                buttonStyles
                { onPress = Just message
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
            InputComponent.textInput
                model.theme
                [ padding (model.theme |> Theme.scaled -2)
                ]
                { onChange = Testing << UpdateDescription
                , text = model.testDescription
                , placeholder = Just (Element.Input.placeholder [] (text "Write a test description here..."))
                , label = Element.Input.labelHidden "Description"
                }
                Nothing

        viewActualOutput : Theme -> Distribution -> TestCase -> FQName -> Element Msg
        viewActualOutput theme ir testCase fQName =
            if List.isEmpty testCase.inputs then
                none

            else
                column [ spacing (theme |> Theme.scaled 1), padding (theme |> Theme.scaled -2) ]
                    (case evaluateOutput ir testCase.inputs fQName of
                        Ok rawValue ->
                            case rawValue of
                                Value.Unit () ->
                                    [ text "Not enough information. Maybe the output depends on an input you have not set yet?" ]

                                expectedOutput ->
                                    [ row [ width fill ] [ el [ Font.bold, Font.size (theme |> Theme.scaled 2) ] (text "Output value: "), el [ Font.heavy, Font.color theme.colors.darkest ] (viewRawValue (insightViewConfig ir) ir rawValue) ]
                                    , column [ width fill, spacing (theme |> Theme.scaled 1) ]
                                        [ descriptionInput
                                        , saveTestCaseButton fQName (Just { testCase | expectedOutput = expectedOutput })
                                        , if Dict.isEmpty model.argStates && model.showSaveTestError then
                                            el [ Font.color model.theme.colors.negative ] <| text " Invalid or missing inputs. Please make sure that every non-optional input is set."

                                          else
                                            none
                                        , if model.selectedTestcaseIndex < 0 then
                                            none

                                          else
                                            updateTestCaseButton fQName { testCase | expectedOutput = expectedOutput }
                                        ]
                                    ]

                        Err _ ->
                            [ row [ width fill ] [ el [ Font.bold, Font.size (theme |> Theme.scaled 2) ] (text "Output value: "), text " Unable to compute " ]
                            , column [ width fill, spacing (theme |> Theme.scaled 1) ]
                                [ descriptionInput
                                , saveTestCaseButton fQName Nothing
                                , if model.showSaveTestError then
                                    el [ Font.color model.theme.colors.negative ] <| text " Invalid or missing inputs. Please make sure that every non-optional input is set."

                                  else
                                    none
                                ]
                            ]
                    )

        evaluateOutput : Distribution -> List (Maybe RawValue) -> FQName -> Result Error RawValue
        evaluateOutput ir inputs fQName =
            evaluateFunctionValue SDK.nativeFunctions ir fQName inputs

        viewRawValue : Morphir.Visual.Config.Config Msg -> Distribution -> RawValue -> Element Msg
        viewRawValue config ir rawValue =
            case fromRawValue ir rawValue of
                Ok typedValue ->
                    el [ centerY ] (ViewValue.viewValue config typedValue)

                Err error ->
                    el [ centerX, centerY ] (text (Infer.typeErrorToMessage error))

        testCoverageMetrics : Distribution -> FQName -> Element Msg
        testCoverageMetrics distro fqName =
            let
                testCases =
                    model.testSuite
                        |> Dict.get fqName
                        |> Maybe.map Array.toList
                        |> Maybe.withDefault []

                maybeValueDef =
                    Distribution.lookupValueDefinition fqName distro
            in
            maybeValueDef
                |> Maybe.map (\valueDef -> getValueBranchCoverage valueDef testCases distro)
                |> Maybe.map
                    (\{ numberOfBranches, numberOfCoveredBranches } ->
                        row
                            [ Border.width 1
                            , Border.color model.theme.colors.darkest
                            , Border.roundEach { topLeft = 5, bottomLeft = 5, topRight = 5, bottomRight = 5 }
                            , padding (model.theme |> Theme.scaled 3)
                            ]
                            [ column []
                                [ row [ Font.bold, Font.size 22, paddingXY 0 10 ] [ text "Test Coverage Percentage - ", text <| String.fromInt (Basics.floor ((toFloat numberOfCoveredBranches / toFloat numberOfBranches) * 100)) ++ "%" ]
                                , row [ Font.bold, Font.size 15, paddingXY 0 10 ] [ text "Break down" ]
                                , row [ Font.bold, Font.size 15, paddingXY 0 10 ] [ text "Number of branches - ", text <| String.fromInt numberOfBranches ]
                                , row [ Font.bold, Font.size 15, paddingXY 0 10 ] [ text "Number of covered branches - ", text <| String.fromInt numberOfCoveredBranches ]
                                ]
                            ]
                    )
                |> Maybe.withDefault (text "")

        scenarios : FQName -> Distribution -> List ( Name, a, Type () ) -> Element Msg
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
                                    , model.theme |> Theme.borderRounded
                                    , Font.size model.theme.fontSize
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
                                    { header =
                                        if columnIndex == maxIndex then
                                            el (Font.bold :: styles) <| Theme.ellipseText columnName

                                        else
                                            el styles <| Theme.ellipseText columnName
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
            testsTable
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
                                                in
                                                Just <|
                                                    TabsComponent.view model.theme
                                                        { onSwitchTab = UI << SwitchTab
                                                        , activeTab = model.activeTabIndex
                                                        , tabs =
                                                            Array.fromList
                                                                [ { name = "Insight View"
                                                                  , content =
                                                                        \_ ->
                                                                            column [ spacing (model.theme |> Theme.scaled 5), paddingXY (model.theme |> Theme.scaled 1) 0 ]
                                                                                [ SectionComponent.view model.theme
                                                                                    { title = "Insight view"
                                                                                    , onToggle = UI (ToggleSection 1)
                                                                                    , isOpen = Set.member 1 model.openSections
                                                                                    , content = \_ -> el [ Theme.borderRounded model.theme, Border.width 1, Border.color model.theme.colors.gray ] <| ViewValue.viewDefinition (insightViewConfig distribution) fullyQualifiedName valueDef
                                                                                    }
                                                                                , SectionComponent.view model.theme
                                                                                    { title = "Inputs & Output"
                                                                                    , onToggle = UI (ToggleSection 2)
                                                                                    , isOpen = Set.member 2 model.openSections
                                                                                    , content =
                                                                                        \_ ->
                                                                                            column
                                                                                                [ spacing
                                                                                                    (model.theme
                                                                                                        |> Theme.scaled 4
                                                                                                    )
                                                                                                ]
                                                                                                [ el [ borderBottom 2, paddingXY 0 5, Border.color model.theme.colors.gray ] (viewArgumentEditors distribution model.argStates valueDef.inputTypes)
                                                                                                , viewActualOutput
                                                                                                    model.theme
                                                                                                    distribution
                                                                                                    { description = "", expectedOutput = Value.toRawValue <| Value.Tuple () [], inputs = inputs }
                                                                                                    fullyQualifiedName
                                                                                                ]
                                                                                    }
                                                                                , SectionComponent.view model.theme
                                                                                    { title = "Test Cases"
                                                                                    , onToggle = UI (ToggleSection 3)
                                                                                    , isOpen = Set.member 3 model.openSections
                                                                                    , content =
                                                                                        \_ ->
                                                                                            column [ spacing (model.theme |> Theme.scaled 4) ]
                                                                                                [ testCoverageMetrics distribution fullyQualifiedName
                                                                                                , scenarios fullyQualifiedName distribution valueDef.inputTypes
                                                                                                ]
                                                                                    }
                                                                                ]
                                                                  }
                                                                , { name = "XRay View"
                                                                  , content = \_ -> XRayView.viewValueDefinition (XRayView.viewType <| pathToUrl) valueDef
                                                                  }
                                                                , { name = "Decorations"
                                                                  , content =
                                                                        \_ ->
                                                                            column
                                                                                [ width fill
                                                                                , height fill
                                                                                , spacing
                                                                                    (model.theme
                                                                                        |> Theme.scaled 8
                                                                                    )
                                                                                , paddingXY 10 10
                                                                                ]
                                                                                [ viewDecorationValues model (ValueID fullyQualifiedName []) ]
                                                                  }
                                                                ]
                                                        }
                                            )
                                        |> Maybe.withDefault none

                                Nothing ->
                                    none

                        Type ( moduleName, typeName ) ->
                            let
                                fullyQualifiedName =
                                    ( packageName, moduleName, typeName )

                                typeDetails =
                                    packageDef.modules
                                        |> Dict.get moduleName
                                        |> Maybe.andThen
                                            (\accessControlledModuleDef ->
                                                accessControlledModuleDef.value.types
                                                    |> Dict.get typeName
                                                    |> Maybe.map
                                                        (\typeDef ->
                                                            ViewType.viewTypeDetails model.theme typeName typeDef.value.value
                                                        )
                                            )
                                        |> Maybe.withDefault none
                            in
                            TabsComponent.view model.theme
                                { onSwitchTab = UI << SwitchTab
                                , activeTab = model.activeTabIndex
                                , tabs =
                                    Array.fromList
                                        [ { name = "Type Details"
                                          , content =
                                                \_ -> typeDetails
                                          }
                                        , { name = "Decorations"
                                          , content =
                                                \_ ->
                                                    column
                                                        [ width fill
                                                        , height fill
                                                        , spacing
                                                            (model.theme
                                                                |> Theme.scaled 8
                                                            )
                                                        , paddingXY 10 10
                                                        ]
                                                        [ viewDecorationValues model (TypeID fullyQualifiedName []) ]
                                          }
                                        ]
                                }

                Nothing ->
                    none

        _ ->
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
                                                Just <|
                                                    Dict.fromList
                                                        (valueDef.inputTypes
                                                            |> List.map
                                                                (\( argName, _, argType ) ->
                                                                    ( argName
                                                                    , ValueEditor.initEditorState distribution argType Nothing
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

        _ ->
            Dict.empty


initInsightViewState : InsightArgumentState -> Morphir.Visual.Config.VisualState
initInsightViewState argState =
    { emptyVisualState
        | variables =
            argState
                |> Dict.map (\_ arg -> arg.lastValidValue |> Maybe.withDefault (Value.Unit ()))
    }


urlFragmentToNodePath : String -> List Path
urlFragmentToNodePath f =
    let
        makeNodePath : String -> List Path -> List Path
        makeNodePath s l =
            case s of
                "" ->
                    l

                _ ->
                    makeNodePath (s |> String.split "." |> List.reverse |> List.drop 1 |> List.reverse |> String.join ".") (l ++ [ Path.fromString s ])
    in
    makeNodePath f []
