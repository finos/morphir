module Morphir.Web.DevelopApp exposing (IRState(..), Model, Msg(..), Page(..), ServerState(..), httpMakeModel, init, main, routeParser, subscriptions, toRoute, update, view, viewBody, viewHeader, viewTitle)

import Array
import Array.Extra
import Browser
import Browser.Navigation as Nav
import Dict exposing (Dict)
import Element exposing (Element, column, el, fill, height, image, layout, link, none, padding, paddingXY, pointer, px, rgb, row, scrollbars, spacing, text, width)
import Element.Background as Background
import Element.Events exposing (onClick)
import Element.Font as Font
import Http exposing (Error(..), emptyBody, jsonBody)
import Morphir.Correctness.Codec exposing (decodeTestSuite, encodeTestSuite)
import Morphir.Correctness.Test exposing (TestCase, TestCases, TestSuite)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.Distribution.Codec as DistributionCodec
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.QName exposing (QName(..))
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, TypedValue, Value)
import Morphir.Visual.Components.TreeLayout as TreeLayout
import Morphir.Visual.Config exposing (Config, PopupScreenRecord)
import Morphir.Visual.Theme as Theme exposing (Theme)
import Morphir.Visual.ValueEditor as ValueEditor
import Morphir.Web.DevelopApp.Common exposing (insertInList, viewAsCard)
import Morphir.Web.DevelopApp.FunctionPage as FunctionPage exposing (TestCaseState)
import Morphir.Web.DevelopApp.ModulePage as ModulePage exposing (makeURL)
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
    }


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
                        case isFunctionPresent of
                            True ->
                                ( { model | currentPage = Module { moduleModel | expandedValues = moduleModel.expandedValues |> Dict.remove ( fQName, localName ) } }, Cmd.none )

                            False ->
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
            case model.currentPage of
                Module moduleModel ->
                    ( { model
                        | currentPage =
                            Module
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
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        InvalidArgValue _ _ _ ->
            ( model, Cmd.none )

        ExpandVariable varIndex maybeRawValue ->
            case model.currentPage of
                Module moduleModel ->
                    ( { model
                        | currentPage =
                            Module
                                { moduleModel | popupVariables = PopupScreenRecord varIndex maybeRawValue }
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        ShrinkVariable varIndex ->
            case model.currentPage of
                Module moduleModel ->
                    ( { model
                        | currentPage =
                            Module
                                { moduleModel | popupVariables = PopupScreenRecord varIndex Nothing }
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

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
                                                                        (case isFunctionPresent of
                                                                            True ->
                                                                                { testCaseState | expandedValues = Dict.remove fQName testCaseState.expandedValues }

                                                                            False ->
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
            ( { model | selectedModule = Just ( nodePath, moduleName ) }, Cmd.none )



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
                    , scrollbars
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
                    viewAsCard model.theme
                        (text "Modules")
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

                Module moduleModel ->
                    ModulePage.viewPage
                        model.theme
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

                Err error ->
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
                    if List.isEmpty childModuleNames then
                        link []
                            { url =
                                "/module/" ++ (currentModule |> List.map Name.toTitleCase |> String.join ".")
                            , label =
                                text (name |> Name.toHumanWords |> String.join " ")
                            }

                    else
                        el
                            [ onClick (SelectModule nodePath currentModule)
                            , pointer
                            ]
                            (text (name |> Name.toHumanWords |> String.join " "))

                Nothing ->
                    text (packageName |> List.map (Name.toHumanWords >> String.join " ") |> String.join " - ")
        )
        Array.empty
        (childModuleNames
            |> List.map
                (\name ->
                    viewModuleNames packageName (currentModule ++ [ name ]) moduleNames
                )
        )
