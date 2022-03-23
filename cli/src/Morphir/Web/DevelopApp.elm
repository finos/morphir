module Morphir.Web.DevelopApp exposing (IRState(..), Model, Msg(..), Page(..), ServerState(..), httpMakeModel, init, main, routeParser, subscriptions, toRoute, update, view, viewBody, viewHeader, viewTitle)

import Array
import Array.Extra
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
        , column
        , el
        , explain
        , fill
        , fillPortion
        , height
        , html
        , image
        , layout
        , link
        , mouseOver
        , none
        , padding
        , paddingXY
        , paragraph
        , pointer
        , px
        , rgb
        , rgba
        , row
        , scrollbars
        , spacing
        , text
        , width
        )
import Element.Background as Background
import Element.Border as Border
import Element.Events exposing (onClick)
import Element.Font as Font
import Element.Input
import Html.Attributes exposing (name)
import Http exposing (Error(..), emptyBody, jsonBody)
import Markdown.Parser as Markdown
import Markdown.Renderer
import Morphir.Correctness.Codec exposing (decodeTestSuite, encodeTestSuite)
import Morphir.Correctness.Test exposing (TestSuite)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.Distribution.Codec as DistributionCodec
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.QName exposing (QName(..))
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, Value)
import Morphir.Visual.Common exposing (nameToText, nameToTitleText)
import Morphir.Visual.Components.TreeLayout as TreeLayout
import Morphir.Visual.Config exposing (PopupScreenRecord)
import Morphir.Visual.Theme as Theme exposing (Theme)
import Morphir.Visual.ValueEditor as ValueEditor
import Morphir.Visual.XRayView as XRayView
import Morphir.Web.DevelopApp.Common exposing (ifThenElse, insertInList, viewAsCard)
import Morphir.Web.DevelopApp.FunctionPage as FunctionPage
import Morphir.Web.DevelopApp.ModulePage as ModulePage exposing (ViewType(..), makeURL)
import Ordering
import Parser exposing (deadEndsToString)
import Set exposing (Set)
import Url exposing (Url)
import Url.Builder
import Url.Parser as UrlParser exposing ((</>), (<?>))



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
    , currentPage : Page
    , theme : Theme
    , irState : IRState
    , serverState : ServerState
    , testSuite : TestSuite
    , functionStates : Dict FQName FunctionPage.Model
    , collapsedModules : Set TreeLayout.NodePath
    , selectedModule : Maybe ( TreeLayout.NodePath, ModuleName )
    , selectedDefinition : Maybe Definition
    , searchText : String
    , showValues : Bool
    , showTypes : Bool
    , simpleDefinitionDetailsModel : ModulePage.Model
    , showModules : Bool
    }


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
    = Home
    | Module ModulePage.Model
    | Function FQName
    | NotFound


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    ( { key = key
      , currentPage = toRoute url
      , theme = Theme.fromConfig Nothing
      , irState = IRLoading
      , serverState = ServerReady
      , testSuite = Dict.empty
      , functionStates = Dict.empty
      , collapsedModules = Set.empty
      , selectedModule = Nothing
      , selectedDefinition = Nothing
      , searchText = ""
      , showValues = True
      , showTypes = True
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
      }
    , Cmd.batch [ httpMakeModel ]
    )



-- UPDATE


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | HttpError Http.Error
    | ServerGetIRResponse Distribution
    | ServerGetTestsResponse TestSuite
    | ExpandReference FQName Bool
    | ExpandVariable Int (Maybe RawValue)
    | ExpandFunctionReference Int FQName Bool
    | ExpandFunctionVariable Int Int (Maybe RawValue)
    | ShrinkFunctionVariable Int Int
    | ShrinkVariable Int
    | ValueFilterChanged String
    | ArgValueUpdated FQName Name ValueEditor.EditorState
    | FunctionInputsUpdated Int Name ValueEditor.EditorState
    | FunctionExpectedOutputUpdated Int ValueEditor.EditorState
    | FunctionDescriptionUpdated Int String
    | InvalidArgValue FQName Name String
    | FunctionAddTestCase
    | FunctionCloneTestCase Int
    | FunctionDeleteTestCase Int
    | FunctionEditTestCase Int
    | FunctionSaveTestCase Int
    | SaveTestSuite FunctionPage.Model
    | ExpandModule TreeLayout.NodePath
    | CollapseModule TreeLayout.NodePath
    | SelectModule TreeLayout.NodePath ModuleName
    | SelectDefinition Definition
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

        updateSimpleDefinitionView : (ModulePage.Model -> ModulePage.Model) -> ( Model, Cmd msg )
        updateSimpleDefinitionView updateModuleModel =
            ( { model | simpleDefinitionDetailsModel = updateModuleModel model.simpleDefinitionDetailsModel }, Cmd.none )
    in
    case msg |> Debug.log "msg" of
        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        UrlChanged url ->
            ( { model | currentPage = toRoute url }
            , Cmd.none
            )

        HttpError httpError ->
            case model.irState of
                IRLoaded _ ->
                    ( model, Cmd.none )

                _ ->
                    ( { model | serverState = ServerHttpError httpError }
                    , Cmd.none
                    )

        ServerGetIRResponse distribution ->
            ( { model | irState = IRLoaded distribution }
            , httpTestModel (IR.fromDistribution distribution)
            )

        ValueFilterChanged filterString ->
            case model.currentPage of
                Module moduleModel ->
                    let
                        newModuleModel =
                            { moduleModel
                                | filter = Just filterString
                            }
                    in
                    ( { model
                        | currentPage = Module newModuleModel
                      }
                    , Nav.replaceUrl model.key
                        (makeURL newModuleModel)
                    )

                _ ->
                    ( model, Cmd.none )

        ExpandReference (( _, moduleName, localName ) as fQName) isFunctionPresent ->
            case model.currentPage of
                Module moduleModel ->
                    if moduleModel.expandedValues |> Dict.member ( fQName, localName ) then
                        if isFunctionPresent then
                            ( { model | currentPage = Module { moduleModel | expandedValues = moduleModel.expandedValues |> Dict.remove ( fQName, localName ) } }, Cmd.none )

                        else
                            ( model, Cmd.none )

                    else
                        ( { model
                            | currentPage =
                                Module
                                    { moduleModel
                                        | expandedValues =
                                            Distribution.lookupValueDefinition (QName moduleName localName)
                                                getDistribution
                                                |> Maybe.map (\valueDef -> moduleModel.expandedValues |> Dict.insert ( fQName, localName ) valueDef)
                                                |> Maybe.withDefault moduleModel.expandedValues
                                    }
                          }
                        , Cmd.none
                        )

                _ ->
                    ( model, Cmd.none )

        ArgValueUpdated fQName argName rawValue ->
            let
                updateModuleModel : ModulePage.Model -> ModulePage.Model
                updateModuleModel moduleModel =
                    { moduleModel
                        | argState =
                            moduleModel.argState
                                |> Dict.update fQName
                                    (\maybeArgs ->
                                        case maybeArgs of
                                            Just args ->
                                                args |> Dict.insert argName rawValue |> Just

                                            Nothing ->
                                                Dict.singleton argName rawValue |> Just
                                    )
                    }
            in
            case model.currentPage of
                Module moduleModel ->
                    ( { model | currentPage = Module (updateModuleModel moduleModel) }, Cmd.none )

                _ ->
                    updateSimpleDefinitionView updateModuleModel

        InvalidArgValue _ _ _ ->
            ( model, Cmd.none )

        ExpandVariable varIndex maybeRawValue ->
            let
                updateModuleModel : ModulePage.Model -> ModulePage.Model
                updateModuleModel moduleModel =
                    { moduleModel | popupVariables = PopupScreenRecord varIndex maybeRawValue }
            in
            case model.currentPage of
                Module moduleModel ->
                    ( { model | currentPage = Module (updateModuleModel moduleModel) }, Cmd.none )

                _ ->
                    updateSimpleDefinitionView updateModuleModel

        ShrinkVariable varIndex ->
            let
                updateModuleModel : ModulePage.Model -> ModulePage.Model
                updateModuleModel moduleModel =
                    { moduleModel | popupVariables = PopupScreenRecord varIndex Nothing }
            in
            case model.currentPage of
                Module moduleModel ->
                    ( { model | currentPage = Module (updateModuleModel moduleModel) }, Cmd.none )

                _ ->
                    updateSimpleDefinitionView updateModuleModel

        ServerGetTestsResponse testSuite ->
            let
                newFunctionState : Dict FQName FunctionPage.Model
                newFunctionState =
                    testSuite
                        |> Dict.toList
                        |> List.map
                            (\( ( packagePath, modulePath, localName ) as fQName, testCasesList ) ->
                                let
                                    testCaseStates =
                                        testCasesList
                                            |> List.map
                                                (\testcase ->
                                                    let
                                                        ( inputArgs, outputArgs ) =
                                                            Distribution.lookupValueSpecification packagePath modulePath localName getDistribution
                                                                |> Maybe.map
                                                                    (\valueSpec ->
                                                                        ( valueSpec.inputs, valueSpec.output )
                                                                    )
                                                                |> Maybe.withDefault ( [], Type.Unit () )
                                                    in
                                                    { expandedValues = Dict.empty
                                                    , popupVariables = PopupScreenRecord 0 Nothing
                                                    , inputStates =
                                                        testcase.inputs
                                                            |> List.map2
                                                                (\( argName, argType ) input ->
                                                                    ( argName, ValueEditor.initEditorState getIR argType (Just input) )
                                                                )
                                                                inputArgs
                                                            |> Dict.fromList
                                                    , expectedOutputState = ValueEditor.initEditorState getIR outputArgs (Just testcase.expectedOutput)
                                                    , descriptionState = testcase.description
                                                    , editMode = False
                                                    }
                                                )
                                            |> Array.fromList
                                in
                                ( fQName
                                , { functionName = fQName
                                  , testCaseStates = testCaseStates
                                  , savedTestCases = testCasesList
                                  }
                                )
                            )
                        |> Dict.fromList
            in
            ( { model | testSuite = testSuite, functionStates = newFunctionState }, Cmd.none )

        ExpandFunctionReference testCaseIndex (( _, moduleName, localName ) as fQName) isFunctionPresent ->
            let
                newFunctionState =
                    case model.currentPage of
                        Function functionName ->
                            let
                                updatedModelState : Dict FQName FunctionPage.Model
                                updatedModelState =
                                    Dict.get functionName model.functionStates
                                        |> Maybe.andThen
                                            (\functionModel ->
                                                functionModel.testCaseStates
                                                    |> Array.get testCaseIndex
                                                    |> Maybe.map
                                                        (\testCaseState ->
                                                            let
                                                                updatedTestCaseStates =
                                                                    Array.set testCaseIndex
                                                                        (if isFunctionPresent then
                                                                            { testCaseState | expandedValues = Dict.remove fQName testCaseState.expandedValues }

                                                                         else
                                                                            Distribution.lookupValueDefinition
                                                                                (QName moduleName localName)
                                                                                getDistribution
                                                                                |> Maybe.map
                                                                                    (\valueDef ->
                                                                                        { testCaseState | expandedValues = Dict.insert fQName valueDef testCaseState.expandedValues }
                                                                                    )
                                                                                |> Maybe.withDefault testCaseState
                                                                        )
                                                                        functionModel.testCaseStates
                                                            in
                                                            Dict.insert functionName { functionModel | testCaseStates = updatedTestCaseStates } model.functionStates
                                                        )
                                            )
                                        |> Maybe.withDefault model.functionStates
                            in
                            updatedModelState

                        _ ->
                            model.functionStates
            in
            ( { model | functionStates = newFunctionState }
            , Cmd.none
            )

        ExpandFunctionVariable testCaseIndex varIndex maybeValue ->
            let
                newFunctionState =
                    case model.currentPage of
                        Function fQName ->
                            let
                                updatedModelState : Dict FQName FunctionPage.Model
                                updatedModelState =
                                    Dict.get fQName model.functionStates
                                        |> Maybe.andThen
                                            (\functionModel ->
                                                functionModel.testCaseStates
                                                    |> Array.get testCaseIndex
                                                    |> Maybe.map
                                                        (\testCaseState ->
                                                            let
                                                                updatedTestCaseStates =
                                                                    Array.set testCaseIndex
                                                                        { testCaseState | popupVariables = PopupScreenRecord varIndex maybeValue }
                                                                        functionModel.testCaseStates
                                                            in
                                                            Dict.insert fQName { functionModel | testCaseStates = updatedTestCaseStates } model.functionStates
                                                        )
                                            )
                                        |> Maybe.withDefault model.functionStates
                            in
                            updatedModelState

                        _ ->
                            model.functionStates
            in
            ( { model | functionStates = newFunctionState }
            , Cmd.none
            )

        ShrinkFunctionVariable testCaseIndex varIndex ->
            let
                newFunctionState =
                    case model.currentPage of
                        Function fQName ->
                            let
                                updatedModelState : Dict FQName FunctionPage.Model
                                updatedModelState =
                                    Dict.get fQName model.functionStates
                                        |> Maybe.andThen
                                            (\functionModel ->
                                                functionModel.testCaseStates
                                                    |> Array.get testCaseIndex
                                                    |> Maybe.map
                                                        (\testCaseState ->
                                                            let
                                                                updatedTestCaseStates =
                                                                    Array.set testCaseIndex
                                                                        { testCaseState | popupVariables = PopupScreenRecord varIndex Nothing }
                                                                        functionModel.testCaseStates
                                                            in
                                                            Dict.insert fQName { functionModel | testCaseStates = updatedTestCaseStates } model.functionStates
                                                        )
                                            )
                                        |> Maybe.withDefault model.functionStates
                            in
                            updatedModelState

                        _ ->
                            model.functionStates
            in
            ( { model | functionStates = newFunctionState }
            , Cmd.none
            )

        FunctionInputsUpdated testCaseIndex argName editorState ->
            let
                newFunctionState =
                    case model.currentPage of
                        Function fQName ->
                            let
                                updatedModelState : Dict FQName FunctionPage.Model
                                updatedModelState =
                                    Dict.get fQName model.functionStates
                                        |> Maybe.andThen
                                            (\functionModel ->
                                                functionModel.testCaseStates
                                                    |> Array.get testCaseIndex
                                                    |> Maybe.map
                                                        (\testCaseState ->
                                                            let
                                                                updatedTestCaseStates =
                                                                    Array.set testCaseIndex
                                                                        { testCaseState | inputStates = Dict.insert argName editorState testCaseState.inputStates }
                                                                        functionModel.testCaseStates
                                                            in
                                                            Dict.insert fQName { functionModel | testCaseStates = updatedTestCaseStates } model.functionStates
                                                        )
                                            )
                                        |> Maybe.withDefault model.functionStates
                            in
                            updatedModelState

                        _ ->
                            model.functionStates
            in
            ( { model | functionStates = newFunctionState }
            , Cmd.none
            )

        FunctionExpectedOutputUpdated testCaseIndex editorState ->
            let
                newFunctionState =
                    case model.currentPage of
                        Function fQName ->
                            let
                                updatedModelState : Dict FQName FunctionPage.Model
                                updatedModelState =
                                    Dict.get fQName model.functionStates
                                        |> Maybe.andThen
                                            (\functionModel ->
                                                functionModel.testCaseStates
                                                    |> Array.get testCaseIndex
                                                    |> Maybe.map
                                                        (\testCaseState ->
                                                            let
                                                                updatedTestCaseStates =
                                                                    Array.set testCaseIndex
                                                                        { testCaseState | expectedOutputState = editorState }
                                                                        functionModel.testCaseStates
                                                            in
                                                            Dict.insert fQName { functionModel | testCaseStates = updatedTestCaseStates } model.functionStates
                                                        )
                                            )
                                        |> Maybe.withDefault model.functionStates
                            in
                            updatedModelState

                        _ ->
                            model.functionStates
            in
            ( { model | functionStates = newFunctionState }
            , Cmd.none
            )

        FunctionDescriptionUpdated testCaseIndex description ->
            let
                newFunctionState =
                    case model.currentPage of
                        Function fQName ->
                            let
                                updatedModelState : Dict FQName FunctionPage.Model
                                updatedModelState =
                                    Dict.get fQName model.functionStates
                                        |> Maybe.andThen
                                            (\functionModel ->
                                                functionModel.testCaseStates
                                                    |> Array.get testCaseIndex
                                                    |> Maybe.map
                                                        (\testCaseState ->
                                                            let
                                                                updatedTestCaseStates =
                                                                    Array.set testCaseIndex
                                                                        { testCaseState | descriptionState = description }
                                                                        functionModel.testCaseStates
                                                            in
                                                            Dict.insert fQName { functionModel | testCaseStates = updatedTestCaseStates } model.functionStates
                                                        )
                                            )
                                        |> Maybe.withDefault model.functionStates
                            in
                            updatedModelState

                        _ ->
                            model.functionStates
            in
            ( { model | functionStates = newFunctionState }
            , Cmd.none
            )

        FunctionAddTestCase ->
            let
                newFunctionState =
                    case model.currentPage of
                        Function (( packagePath, modulePath, localName ) as fQName) ->
                            let
                                emptyFunctionModel =
                                    FunctionPage.Model fQName Array.empty []

                                ( inputArgValues, outputValue ) =
                                    Distribution.lookupValueSpecification packagePath modulePath localName getDistribution
                                        |> Maybe.map
                                            (\valueSpec ->
                                                ( valueSpec.inputs, valueSpec.output )
                                            )
                                        |> Maybe.withDefault ( [], Type.Unit () )

                                updatedModelState : Dict FQName FunctionPage.Model
                                updatedModelState =
                                    Dict.get fQName model.functionStates
                                        |> Maybe.withDefault emptyFunctionModel
                                        |> (\functionModel ->
                                                let
                                                    testCaseStates =
                                                        functionModel.testCaseStates
                                                            |> Array.push
                                                                { expandedValues = Dict.empty
                                                                , popupVariables = PopupScreenRecord 0 Nothing
                                                                , inputStates =
                                                                    List.map
                                                                        (\( argName, argType ) ->
                                                                            ( argName, ValueEditor.initEditorState getIR argType Nothing )
                                                                        )
                                                                        inputArgValues
                                                                        |> Dict.fromList
                                                                , expectedOutputState = ValueEditor.initEditorState getIR outputValue Nothing
                                                                , descriptionState = ""
                                                                , editMode = True
                                                                }
                                                in
                                                Dict.insert fQName { functionModel | testCaseStates = testCaseStates } model.functionStates
                                           )
                            in
                            updatedModelState

                        _ ->
                            model.functionStates
            in
            ( { model | functionStates = newFunctionState }
            , Cmd.none
            )

        FunctionCloneTestCase testCaseIndex ->
            let
                newFunctionState =
                    case model.currentPage of
                        Function fQName ->
                            let
                                updatedModelState : Dict FQName FunctionPage.Model
                                updatedModelState =
                                    Dict.get fQName model.functionStates
                                        |> Maybe.map
                                            (\functionModel ->
                                                let
                                                    testCaseStates =
                                                        functionModel.testCaseStates
                                                            |> Array.toList
                                                            |> insertInList testCaseIndex
                                                            |> Array.fromList
                                                in
                                                Dict.insert fQName { functionModel | testCaseStates = testCaseStates } model.functionStates
                                            )
                                        |> Maybe.withDefault model.functionStates
                            in
                            updatedModelState

                        _ ->
                            model.functionStates
            in
            ( { model | functionStates = newFunctionState }
            , Cmd.none
            )

        FunctionDeleteTestCase testCaseIndex ->
            let
                newFunctionState =
                    case model.currentPage of
                        Function functionName ->
                            let
                                updatedModelState : Dict FQName FunctionPage.Model
                                updatedModelState =
                                    Dict.get functionName model.functionStates
                                        |> Maybe.map
                                            (\functionModel ->
                                                Dict.insert functionName
                                                    { functionModel
                                                        | testCaseStates =
                                                            functionModel.testCaseStates
                                                                |> Array.Extra.removeAt testCaseIndex
                                                    }
                                                    model.functionStates
                                            )
                                        |> Maybe.withDefault model.functionStates
                            in
                            updatedModelState

                        _ ->
                            model.functionStates
            in
            ( { model | functionStates = newFunctionState }
            , Cmd.none
            )

        FunctionEditTestCase testCaseIndex ->
            let
                newFunctionState =
                    case model.currentPage of
                        Function fQName ->
                            let
                                updatedModelState : Dict FQName FunctionPage.Model
                                updatedModelState =
                                    Dict.get fQName model.functionStates
                                        |> Maybe.andThen
                                            (\functionModel ->
                                                functionModel.testCaseStates
                                                    |> Array.get testCaseIndex
                                                    |> Maybe.map
                                                        (\testCaseState ->
                                                            let
                                                                updatedTestCaseStates =
                                                                    Array.set testCaseIndex
                                                                        { testCaseState | editMode = True }
                                                                        functionModel.testCaseStates
                                                            in
                                                            Dict.insert fQName { functionModel | testCaseStates = updatedTestCaseStates } model.functionStates
                                                        )
                                            )
                                        |> Maybe.withDefault model.functionStates
                            in
                            updatedModelState

                        _ ->
                            model.functionStates
            in
            ( { model | functionStates = newFunctionState }
            , Cmd.none
            )

        FunctionSaveTestCase testCaseIndex ->
            let
                newFunctionState =
                    case model.currentPage of
                        Function fQName ->
                            let
                                updatedModelState : Dict FQName FunctionPage.Model
                                updatedModelState =
                                    Dict.get fQName model.functionStates
                                        |> Maybe.andThen
                                            (\functionModel ->
                                                functionModel.testCaseStates
                                                    |> Array.get testCaseIndex
                                                    |> Maybe.map
                                                        (\testCaseState ->
                                                            let
                                                                isOutputEmpty : Bool
                                                                isOutputEmpty =
                                                                    testCaseState.expectedOutputState.lastValidValue == Nothing

                                                                isInputEmpty : Bool
                                                                isInputEmpty =
                                                                    testCaseState.inputStates
                                                                        |> Dict.toList
                                                                        |> List.foldl
                                                                            (\( _, argValue ) val2 ->
                                                                                (argValue.lastValidValue == Nothing) || val2
                                                                            )
                                                                            False

                                                                updatedTestCaseStates =
                                                                    Array.set testCaseIndex
                                                                        { testCaseState | editMode = isOutputEmpty || isInputEmpty }
                                                                        functionModel.testCaseStates
                                                            in
                                                            Dict.insert fQName { functionModel | testCaseStates = updatedTestCaseStates } model.functionStates
                                                        )
                                            )
                                        |> Maybe.withDefault model.functionStates
                            in
                            updatedModelState

                        _ ->
                            model.functionStates
            in
            ( { model | functionStates = newFunctionState }
            , Cmd.none
            )

        SaveTestSuite functionModel ->
            let
                isEditModeOn =
                    functionModel.testCaseStates
                        |> Array.toList
                        |> List.foldl
                            (\testCaseState boolVal ->
                                testCaseState.editMode || boolVal
                            )
                            False
            in
            if isEditModeOn then
                ( model, Cmd.none )

            else
                let
                    ( packagePath, modulePath, localName ) =
                        functionModel.functionName

                    argNames =
                        Distribution.lookupValueSpecification packagePath modulePath localName getDistribution
                            |> Maybe.map (\valueSpec -> valueSpec.inputs)
                            |> Maybe.withDefault []

                    newTestSuite =
                        Dict.insert functionModel.functionName
                            (functionModel.testCaseStates
                                |> Array.toList
                                |> List.map
                                    (\testCaseState ->
                                        { inputs =
                                            List.map
                                                (\( name, _ ) ->
                                                    Dict.get name testCaseState.inputStates
                                                        |> Maybe.andThen .lastValidValue
                                                        |> Maybe.withDefault (Value.Unit ())
                                                )
                                                argNames
                                        , expectedOutput =
                                            testCaseState.expectedOutputState.lastValidValue
                                                |> Maybe.withDefault (Value.Unit ())
                                        , description = testCaseState.descriptionState
                                        }
                                    )
                            )
                            model.testSuite
                in
                ( { model | testSuite = newTestSuite }, httpSaveTestSuite getIR newTestSuite )

        ExpandModule nodePath ->
            ( { model | collapsedModules = model.collapsedModules |> Set.remove nodePath }, Cmd.none )

        CollapseModule nodePath ->
            ( { model | collapsedModules = model.collapsedModules |> Set.insert nodePath }, Cmd.none )

        SelectModule nodePath moduleName ->
            ( { model
                | selectedModule = Just ( nodePath, moduleName )
                , selectedDefinition = Nothing
                , showModules = False
              }
            , Cmd.none
            )

        SelectDefinition definition ->
            ( { model | selectedDefinition = Just definition }, Cmd.none )

        SearchDefinition defName ->
            ( { model | searchText = defName }, Cmd.none )

        ToggleValues isToggled ->
            ( { model | showValues = isToggled }, Cmd.none )

        ToggleTypes isToggled ->
            ( { model | showTypes = isToggled }, Cmd.none )

        ToggleModulesMenu ->
            ( { model
                | showModules = not model.showModules
              }
            , Cmd.none
            )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- ROUTE


routeParser : UrlParser.Parser (Page -> a) a
routeParser =
    UrlParser.oneOf
        [ UrlParser.map Home UrlParser.top
        , UrlParser.map Module ModulePage.routeParser
        , UrlParser.map Function FunctionPage.routeParser
        , UrlParser.map (always Home) UrlParser.string
        ]


toRoute : Url -> Page
toRoute url =
    UrlParser.parse routeParser url
        |> Maybe.withDefault NotFound



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = viewTitle model
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


viewTitle : Model -> String
viewTitle model =
    case model.currentPage of
        Home ->
            "Morphir - Home"

        Module moduleModel ->
            ModulePage.viewTitle moduleModel

        NotFound ->
            "Morphir - Not Found"

        Function functionModel ->
            FunctionPage.viewTitle functionModel


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

        IRLoaded ((Library packageName _ packageDef) as distribution) ->
            case model.currentPage of
                Home ->
                    viewHome model packageName packageDef

                Module moduleModel ->
                    viewModuleModel model.theme moduleModel distribution

                NotFound ->
                    text "Route not found"

                Function functionName ->
                    let
                        functionPageModel : FunctionPage.Model
                        functionPageModel =
                            model.functionStates
                                |> Dict.get functionName
                                |> Maybe.withDefault
                                    { functionName = functionName
                                    , testCaseStates = Array.empty
                                    , savedTestCases = []
                                    }
                    in
                    FunctionPage.viewPage
                        model.theme
                        { expandReference = ExpandFunctionReference
                        , expandVariable = ExpandFunctionVariable
                        , shrinkVariable = ShrinkFunctionVariable
                        , inputsUpdated = FunctionInputsUpdated
                        , expectedOutputUpdated = FunctionExpectedOutputUpdated
                        , descriptionUpdated = FunctionDescriptionUpdated
                        , addTestCase = FunctionAddTestCase
                        , cloneTestCase = FunctionCloneTestCase
                        , deleteTestCase = FunctionDeleteTestCase
                        , editTestCase = FunctionEditTestCase
                        , saveTestCase = FunctionSaveTestCase
                        , saveTestSuite = SaveTestSuite
                        }
                        distribution
                        functionPageModel


viewModuleModel : Theme -> ModulePage.Model -> Distribution -> Element Msg
viewModuleModel theme moduleModel distribution =
    ModulePage.viewPage
        theme
        { expandReference = ExpandReference
        , expandVariable = ExpandVariable
        , shrinkVariable = ShrinkVariable
        , argValueUpdated = ArgValueUpdated
        , invalidArgValue = InvalidArgValue
        , jumpToTestCases = \fQName -> LinkClicked (Browser.External (Url.Builder.absolute [ "function", FQName.toString fQName ] []))
        }
        ValueFilterChanged
        distribution
        moduleModel


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
            , scrollbars
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
                createUiElement : Element Msg -> Definition -> Name -> Element Msg
                createUiElement icon definition name =
                    viewAsLabel
                        (SelectDefinition definition)
                        model.theme
                        icon
                        (text (nameToText name))
                        (moduleNameToPathString moduleName)

                types : List ( Definition, Element Msg )
                types =
                    moduleDef.types
                        |> Dict.toList
                        |> List.map
                            (\( typeName, _ ) ->
                                ( Type ( moduleName, typeName )
                                , createUiElement (el [ Font.color (rgba 0 0.639 0.882 0.6) ] (text "ⓣ ")) (Type ( moduleName, typeName )) typeName
                                )
                            )

                values : List ( Definition, Element Msg )
                values =
                    moduleDef.values
                        |> Dict.toList
                        |> List.map
                            (\( valueName, _ ) ->
                                ( Value ( moduleName, valueName )
                                , createUiElement (el [ Font.color (rgba 1 0.411 0 0.6) ] (text "ⓥ ")) (Value ( moduleName, valueName )) valueName
                                )
                            )
            in
            ifThenElse model.showValues values [] ++ ifThenElse model.showTypes types []

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
                            String.contains model.searchText (nameToText defName)
                    in
                    List.filter
                        (\( definition, _ ) ->
                            definition
                                |> definitionName
                                |> searchTextContainsDefName
                        )
                        definitions

                paintSelectedElement : List ( Definition, Element Msg ) -> List (Element Msg)
                paintSelectedElement =
                    let
                        paintIfSelected : Element Msg -> Element Msg
                        paintIfSelected elem =
                            el [ Background.color model.theme.colors.selectionColor, width fill ] elem
                    in
                    List.map
                        (\( def, elem ) ->
                            case model.selectedDefinition of
                                Just selected ->
                                    if selected == def then
                                        paintIfSelected elem

                                    else
                                        Theme.defaultClickableListElem model.theme elem

                                Nothing ->
                                    Theme.defaultClickableListElem model.theme elem
                        )

                defaultIfUnselected : List (Element Msg) -> List (Element Msg)
                defaultIfUnselected definitionElementList =
                    if List.isEmpty definitionElementList then
                        if model.searchText == "" then
                            [ text "Please select a module on the left!" ]

                        else
                            [ text "No matching definition in this module." ]

                    else
                        definitionElementList
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
                |> paintSelectedElement
                |> defaultIfUnselected
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
                , text = model.searchText
                , placeholder = Just (Element.Input.placeholder [] (text "Search for a definition"))
                , label = Element.Input.labelHidden "Search"
                }

        valueCheckbox : Element Msg
        valueCheckbox =
            Element.Input.checkbox
                [ width (fillPortion 2) ]
                { onChange = ToggleValues
                , checked = model.showValues
                , icon = Element.Input.defaultCheckbox
                , label = Element.Input.labelLeft [] (text "values:")
                }

        typeCheckbox : Element Msg
        typeCheckbox =
            Element.Input.checkbox
                [ width (fillPortion 2) ]
                { onChange = ToggleTypes
                , checked = model.showTypes
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
                , label = text (ifThenElse model.showModules " hide Modules ↑ " " show Modules ↓ ")
                }

        moduleTree =
            el
                scrollableListStyles
                (TreeLayout.view TreeLayout.defaultTheme
                    { onCollapse = CollapseModule
                    , onExpand = ExpandModule
                    , collapsedPaths = model.collapsedModules
                    , selectedPaths =
                        model.selectedModule
                            |> Maybe.map (Tuple.first >> Set.singleton)
                            |> Maybe.withDefault Set.empty
                    }
                    (viewModuleNames packageName
                        []
                        (packageDef.modules |> Dict.keys)
                    )
                )

        pathToSelectedModule : String
        pathToSelectedModule =
            case model.selectedModule |> Maybe.map Tuple.second of
                Just moduleName ->
                    moduleNameToPathString moduleName

                _ ->
                    ""
    in
    row [ width fill, height fill, Background.color gray, spacing 10 ]
        [ column
            [ width (ifThenElse model.showModules (fillPortion 4) (fillPortion 2))
            , height fill
            ]
            [ ifThenElse model.showModules
                none
                (row
                    [ width fill
                    , padding (model.theme |> Theme.scaled -3)
                    , spacing (model.theme |> Theme.scaled 1)
                    ]
                    [ el [ centerX, Font.bold ]
                        (text pathToSelectedModule)
                    , el [ alignRight ] toggleModulesMenu
                    ]
                )
            , row
                [ height fill
                , width fill
                , spacing 10
                ]
                [ column
                    [ Background.color gray
                    , height fill
                    , width (ifThenElse model.showModules (fillPortion 2) (fillPortion 0))
                    ]
                    [ row
                        [ width fill
                        , paddingXY 0 (model.theme |> Theme.scaled -3)
                        ]
                        [ ifThenElse model.showModules (el [ alignRight ] toggleModulesMenu) none ]
                    , ifThenElse model.showModules moduleTree none
                    ]
                , column
                    [ Background.color gray
                    , height fill
                    , width (ifThenElse model.showModules (fillPortion 3) fill)
                    ]
                    [ row
                        [ width fill
                        , spacing (model.theme |> Theme.scaled 1)
                        , paddingXY 0 (model.theme |> Theme.scaled -5)
                        ]
                        [ definitionFilter, row [ alignRight, spacing (model.theme |> Theme.scaled 1) ] [ valueCheckbox, typeCheckbox ] ]
                    , el
                        scrollableListStyles
                        (viewDefinitionLabels (model.selectedModule |> Maybe.map Tuple.second))
                    ]
                ]
            ]
        , column
            [ height fill
            , width (ifThenElse model.showModules (fillPortion 6) (fillPortion 7))
            , Background.color model.theme.colors.lightest
            ]
            [ column [ width fill, height (fillPortion 2), scrollbars, padding (model.theme |> Theme.scaled 1) ] [ viewDefinition model.selectedDefinition ]
            , column [ width fill, height (fillPortion 3), Border.widthXY 0 8, Border.color gray ]
                [ el [ height fill, width fill ]
                    (viewDefinitionDetails model.theme model.irState model.simpleDefinitionDetailsModel model.selectedDefinition)
                ]
            ]
        ]


viewType : Theme -> Name -> Type.Definition () -> String -> Element msg
viewType theme typeName typeDef docs =
    case typeDef of
        Type.TypeAliasDefinition _ (Type.Record _ fields) ->
            let
                fieldNames =
                    \field ->
                        el
                            (Theme.boldLabelStyles theme)
                            (text (nameToText field.name))

                fieldTypes =
                    \field ->
                        el
                            (Theme.labelStyles theme)
                            (XRayView.viewType field.tpe)

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
                    (XRayView.viewType body)
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

                isEnum =
                    accessControlledConstructors.value
                        |> Dict.values
                        |> List.all List.isEmpty

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
                                el [ padding (theme |> Theme.scaled -2) ] (XRayView.viewType baseType)

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
                                                    |> List.map (Tuple.second >> XRayView.viewType)
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
        cardTitle =
            link []
                { url =
                    "/module/" ++ (moduleName |> List.map Name.toTitleCase |> String.join ".") ++ "?filter=" ++ nameToText valueName
                , label =
                    text (nameToText valueName)
                }

        isData =
            List.isEmpty valueDef.inputTypes

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


viewAsLabel : msg -> Theme -> Element msg -> Element msg -> String -> Element msg
viewAsLabel clickMessage theme icon header class =
    row
        [ width fill
        , Font.size (theme |> Theme.scaled 2)
        , onClick clickMessage
        , pointer
        ]
        [ icon
        , el
            [ Font.bold
            , paddingXY (theme |> Theme.scaled -10) (theme |> Theme.scaled -3)
            ]
            header
        , el
            [ alignRight
            , Font.color theme.colors.secondaryInformation
            , paddingXY (theme |> Theme.scaled -10) (theme |> Theme.scaled -3)
            ]
            (el [] (text class))
        ]



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


viewModuleNames : PackageName -> ModuleName -> List ModuleName -> TreeLayout.Node Msg
viewModuleNames packageName currentModule moduleNames =
    let
        currentModuleName =
            currentModule
                |> List.reverse
                |> List.head

        childModuleNames =
            moduleNames
                |> List.filterMap
                    (\moduleName ->
                        if currentModule |> Path.isPrefixOf moduleName then
                            moduleName |> List.drop (List.length currentModule) |> List.head

                        else
                            Nothing
                    )
                |> Set.fromList
                |> Set.toList
    in
    TreeLayout.Node
        (\nodePath ->
            case currentModuleName of
                Just name ->
                    el
                        [ onClick (SelectModule nodePath currentModule)
                        , pointer
                        ]
                        (text (name |> nameToTitleText))

                Nothing ->
                    el
                        [ onClick (SelectModule nodePath currentModule)
                        , pointer
                        ]
                        (text (packageName |> List.map nameToTitleText |> String.join " - "))
        )
        Array.empty
        (childModuleNames
            |> List.map
                (\name ->
                    viewModuleNames packageName (currentModule ++ [ name ]) moduleNames
                )
        )


definitionName : Definition -> Name
definitionName definition =
    case definition of
        Value ( _, valueName ) ->
            valueName

        Type ( _, typeName ) ->
            typeName


moduleNameToPathString : ModuleName -> String
moduleNameToPathString moduleName =
    Path.toString (Name.toHumanWords >> String.join " ") " / " moduleName


viewDefinitionDetails : Theme -> IRState -> ModulePage.Model -> Maybe Definition -> Element Msg
viewDefinitionDetails theme irState moduleModel maybeSelectedDefinition =
    let
        updatedModel : Path -> Name -> ModulePage.Model
        updatedModel moduleName filterValue =
            { moduleModel
                | filter = Just (nameToText filterValue)
                , moduleName = Path.toList moduleName |> List.map nameToText
            }
    in
    case irState of
        IRLoading ->
            none

        IRLoaded ((Library _ _ packageDef) as distribution) ->
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
                                                    viewModuleModel theme (updatedModel moduleName valueName) distribution
                                                )
                                    )
                                |> Maybe.withDefault none

                        Type _ ->
                            none

                Nothing ->
                    none
