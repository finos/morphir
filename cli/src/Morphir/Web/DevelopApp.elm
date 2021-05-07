module Morphir.Web.DevelopApp exposing (IRState(..), Model, Msg(..), Page(..), ServerState(..), httpMakeModel, init, main, routeParser, subscriptions, toRoute, update, view, viewBody, viewHeader, viewTitle)

import Array exposing (Array)
import Browser
import Browser.Navigation as Nav
import Dict exposing (Dict)
import Element exposing (Element, column, el, fill, height, image, layout, link, none, padding, paddingXY, px, rgb, row, spacing, text, width)
import Element.Background as Background
import Element.Font as Font
import Http
import Morphir.Correctness.Codec exposing (decodeTestSuite)
import Morphir.Correctness.Test exposing (TestCase, TestCases, TestSuite)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.Distribution.Codec as DistributionCodec
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.QName exposing (QName(..))
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, TypedValue, Value)
import Morphir.Visual.Config exposing (Config, PopupScreenRecord)
import Morphir.Web.DevelopApp.Common exposing (scaled, viewAsCard)
import Morphir.Web.DevelopApp.FunctionPage as FunctionPage exposing (TestCaseState)
import Morphir.Web.DevelopApp.ModulePage as ModulePage exposing (makeURL)
import Morphir.Web.Theme exposing (Theme)
import Morphir.Web.Theme.Light as Light
import Url exposing (Url)
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
    , theme : Theme Msg
    , irState : IRState
    , serverState : ServerState
    , testSuite : TestSuite
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
    | Function FunctionPage.Model
    | NotFound


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    ( { key = key
      , currentPage = toRoute url
      , theme = Light.theme scaled
      , irState = IRLoading
      , serverState = ServerReady
      , testSuite = Dict.empty
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
    | ArgValueUpdated FQName Name RawValue
    | InvalidArgValue FQName Name String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
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
            , httpTestModel distribution
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
                                                (case model.irState of
                                                    IRLoaded distribution ->
                                                        distribution

                                                    _ ->
                                                        Library [] Dict.empty Package.emptyDefinition
                                                )
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

        InvalidArgValue fQName argName string ->
            ( model, Cmd.none )

        ExpandVariable varIndex maybeRawValue ->
            case model.currentPage of
                Module moduleModel ->
                    ( { model
                        | currentPage =
                            Module
                                { moduleModel | popupVariables = { variableIndex = varIndex, variableValue = maybeRawValue } }
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
                                { moduleModel | popupVariables = { variableIndex = varIndex, variableValue = Nothing } }
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        ServerGetTestsResponse testSuite ->
            ( { model | testSuite = testSuite }, Cmd.none )

        ExpandFunctionReference testCaseIndex (( _, moduleName, localName ) as fQName) isFunctionPresent ->
            case model.currentPage of
                Function functionModel ->
                    let
                        oldTestCaseState =
                            Dict.get testCaseIndex functionModel.testCaseStates
                                |> Maybe.withDefault
                                    { expandedValues = Dict.empty
                                    , popupVariables = { variableIndex = 0, variableValue = Nothing }
                                    }

                        newTestCaseStates : Dict FQName (Value.Definition () (Type ())) -> Dict Int TestCaseState
                        newTestCaseStates newExpendedValues =
                            Dict.insert testCaseIndex { oldTestCaseState | expandedValues = newExpendedValues } functionModel.testCaseStates
                    in
                    if oldTestCaseState.expandedValues |> Dict.member fQName then
                        case isFunctionPresent of
                            True ->
                                ( { model
                                    | currentPage =
                                        Function
                                            { functionModel
                                                | testCaseStates =
                                                    newTestCaseStates (oldTestCaseState.expandedValues |> Dict.remove fQName)
                                            }
                                  }
                                , Cmd.none
                                )

                            False ->
                                ( model, Cmd.none )

                    else
                        ( { model
                            | currentPage =
                                Function
                                    { functionModel
                                        | testCaseStates =
                                            newTestCaseStates
                                                (Distribution.lookupValueDefinition (QName moduleName localName)
                                                    (case model.irState of
                                                        IRLoaded distribution ->
                                                            distribution

                                                        _ ->
                                                            Library [] Dict.empty Package.emptyDefinition
                                                    )
                                                    |> Maybe.map (\valueDef -> oldTestCaseState.expandedValues |> Dict.insert fQName valueDef)
                                                    |> Maybe.withDefault oldTestCaseState.expandedValues
                                                )
                                    }
                          }
                        , Cmd.none
                        )

                _ ->
                    ( model, Cmd.none )

        ExpandFunctionVariable testCaseIndex varIndex maybeValue ->
            case model.currentPage of
                Function functionModel ->
                    let
                        popupVariables =
                            { variableIndex = varIndex, variableValue = maybeValue }

                        oldTestCaseState =
                            Dict.get testCaseIndex functionModel.testCaseStates
                                |> Maybe.withDefault
                                    { expandedValues = Dict.empty
                                    , popupVariables = popupVariables
                                    }

                        newTestCaseStates : Dict Int TestCaseState
                        newTestCaseStates =
                            Dict.insert testCaseIndex { oldTestCaseState | popupVariables = popupVariables } functionModel.testCaseStates
                    in
                    ( { model
                        | currentPage =
                            Function
                                { functionModel | testCaseStates = newTestCaseStates }
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        ShrinkFunctionVariable testCaseIndex varIndex ->
            case model.currentPage of
                Function functionModel ->
                    let
                        popupVariables =
                            { variableIndex = varIndex, variableValue = Nothing }

                        oldTestCaseState =
                            Dict.get testCaseIndex functionModel.testCaseStates
                                |> Maybe.withDefault
                                    { expandedValues = Dict.empty
                                    , popupVariables = popupVariables
                                    }

                        newTestCaseStates : Dict Int TestCaseState
                        newTestCaseStates =
                            Dict.insert testCaseIndex { oldTestCaseState | popupVariables = popupVariables } functionModel.testCaseStates
                    in
                    ( { model
                        | currentPage =
                            Function
                                { functionModel | testCaseStates = newTestCaseStates }
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )



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
            , Font.size (scaled 2)
            , width fill
            ]
            (column
                [ width fill
                ]
                [ viewHeader model
                , case model.serverState of
                    ServerReady ->
                        none

                    ServerHttpError error ->
                        viewServerError error
                , el [ padding 5, width fill ] (viewBody model)
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
        , Background.color model.theme.highlightColor
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
                , el [ paddingXY 10 0 ]
                    (model.theme.heading 1 "Morphir Web")
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
                    viewAsCard (text "Modules")
                        (column
                            [ padding 10
                            , spacing 10
                            ]
                            (packageDef.modules
                                |> Dict.toList
                                |> List.map
                                    (\( moduleName, accessControlledModuleDef ) ->
                                        link []
                                            { url =
                                                "/module/" ++ (moduleName |> List.map Name.toTitleCase |> String.join ".")
                                            , label =
                                                moduleName
                                                    |> List.map (Name.toHumanWords >> String.join " ")
                                                    |> String.join " / "
                                                    |> text
                                            }
                                    )
                            )
                        )

                Module moduleModel ->
                    ModulePage.viewPage
                        { expandReference = ExpandReference
                        , expandVariable = ExpandVariable
                        , shrinkVariable = ShrinkVariable
                        , argValueUpdated = ArgValueUpdated
                        , invalidArgValue = InvalidArgValue
                        }
                        ValueFilterChanged
                        distribution
                        moduleModel

                NotFound ->
                    text "Route not found"

                Function functionModel ->
                    FunctionPage.viewPage
                        { expandReference = ExpandFunctionReference
                        , expandVariable = ExpandFunctionVariable
                        , shrinkVariable = ShrinkFunctionVariable
                        }
                        (Dict.get functionModel.functionName model.testSuite |> Maybe.withDefault [])
                        distribution
                        functionModel



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


httpTestModel : Distribution -> Cmd Msg
httpTestModel distribution =
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
                (decodeTestSuite (IR.fromDistribution distribution))
        }
