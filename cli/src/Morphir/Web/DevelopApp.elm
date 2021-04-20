module Morphir.Web.DevelopApp exposing (IRState(..), Model, Msg(..), Route(..), ServerState(..), ViewType(..), httpMakeModel, init, main, makeURL, noBorderWidth, routeParser, scaled, subscriptions, toRoute, update, view, viewAsCard, viewBody, viewHeader, viewModuleControls, viewTitle, viewTypeFromString, viewValue)

import Browser
import Browser.Navigation as Nav
import Dict exposing (Dict)
import Element exposing (Element, alignTop, centerX, centerY, column, el, fill, height, image, layout, link, minimum, none, padding, paddingXY, px, rgb, row, scrollbarX, scrollbars, shrink, spacing, text, width, wrappedRow)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input exposing (labelHidden)
import Http
import Morphir.Correctness.Codec exposing (decodeTestSuite)
import Morphir.Correctness.Test exposing (TestCase, TestCases, TestSuite)
import Morphir.Elm.Frontend as Frontend
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.Distribution.Codec as DistributionCodec
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.QName as QName
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, TypedValue, Value, indexedMapValue)
import Morphir.Type.Infer as Infer exposing (TypeError)
import Morphir.Value.Interpreter as Interpreter
import Morphir.Visual.Config exposing (Config, PopupScreenRecord)
import Morphir.Visual.Edit as Edit
import Morphir.Visual.Theme as Theme
import Morphir.Visual.ViewValue as ViewValue
import Morphir.Visual.VisualTypedValue exposing (VisualTypedValue, rawToVisualTypedValue)
import Morphir.Visual.XRayView as XRayView
import Morphir.Web.Theme exposing (Theme)
import Morphir.Web.Theme.Light as Light
import Url exposing (Url)
import Url.Parser as UrlParser exposing ((</>), (<?>))
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
    , route : Route
    , theme : Theme Msg
    , irState : IRState
    , serverState : ServerState
    , argState : Dict FQName (Dict Name RawValue)
    , expandedValues : Dict ( FQName, Name ) (Value.Definition () (Type ()))
    , testSuite : TestSuite
    }


type IRState
    = IRLoading
    | IRLoaded Distribution


type ServerState
    = ServerReady
    | ServerHttpError Http.Error


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    ( { key = key
      , route = toRoute url
      , theme = Light.theme scaled
      , irState = IRLoading
      , serverState = ServerReady
      , argState = Dict.empty
      , expandedValues = Dict.empty
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
            ( { model | route = toRoute url }
            , Cmd.none
            )

        HttpError httpError ->
            ( { model | serverState = ServerHttpError httpError }
            , Cmd.none
            )

        ServerGetIRResponse distribution ->
            ( { model | irState = IRLoaded distribution }
            , httpTestModel distribution
            )

        ValueFilterChanged filterString ->
            let
                newRoute =
                    case model.route of
                        Module moduleName _ viewType ->
                            Module moduleName (Just filterString) viewType

                        _ ->
                            model.route

                cmd =
                    case model.route of
                        Module moduleName filter viewType ->
                            Nav.replaceUrl model.key
                                (makeURL moduleName (Just filterString) viewType)

                        _ ->
                            Cmd.none
            in
            ( { model | route = newRoute }
            , cmd
            )

        ExpandReference fqn isFunctionPresent ->
            ( model, Cmd.none )

        ArgValueUpdated fQName argName rawValue ->
            ( { model
                | argState =
                    model.argState
                        |> Dict.update fQName
                            (\maybeArgs ->
                                case maybeArgs of
                                    Just args ->
                                        args |> Dict.insert argName rawValue |> Just

                                    Nothing ->
                                        Dict.singleton argName rawValue |> Just
                            )
              }
            , Cmd.none
            )

        InvalidArgValue fQName argName string ->
            ( model, Cmd.none )

        ExpandVariable varIndex maybeRawValue ->
            ( model, Cmd.none )

        ShrinkVariable varIndex ->
            ( model, Cmd.none )

        ServerGetTestsResponse testSuite ->
            ( { model | testSuite = testSuite }
            , Cmd.none
            )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- ROUTE


type Route
    = Home
    | Module (List String) (Maybe String) ViewType
    | Function FQName
    | NotFound


type ViewType
    = XRayView
    | InsightView


viewTypeFromString : String -> ViewType
viewTypeFromString string =
    case string of
        "insight" ->
            InsightView

        _ ->
            XRayView


routeParser : UrlParser.Parser (Route -> a) a
routeParser =
    UrlParser.oneOf
        [ UrlParser.map Home UrlParser.top
        , UrlParser.map
            (\moduleName filter viewType ->
                Module moduleName
                    (filter
                        |> Maybe.map
                            (\filterString ->
                                if String.endsWith "*" filterString then
                                    filterString |> String.dropRight 1

                                else
                                    filterString
                            )
                    )
                    viewType
            )
            (UrlParser.s "module"
                </> (UrlParser.string |> UrlParser.map (String.split "."))
                <?> Query.string "filter"
                <?> (Query.string "view" |> Query.map (Maybe.map viewTypeFromString >> Maybe.withDefault InsightView))
            )
        , UrlParser.map (\fqName -> Function fqName)
            (UrlParser.s "function"
                </> (UrlParser.string
                        |> UrlParser.map
                            (\string ->
                                FQName.fromString string ":"
                            )
                    )
            )
        , UrlParser.map (always Home) UrlParser.string
        ]


toRoute : Url -> Route
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
    case model.route of
        Home ->
            "Morphir - Home"

        Module moduleName _ _ ->
            "Morphir - " ++ (moduleName |> String.join " / ")

        NotFound ->
            "Morphir - Not Found"

        Function fqName ->
            "Morphir - " ++ (fqName |> FQName.toString)


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
            case model.route of
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

                Module moduleNameString filterString viewType ->
                    let
                        moduleName =
                            moduleNameString |> List.map Name.fromString
                    in
                    case packageDef.modules |> Dict.get moduleName of
                        Just accessControlledModuleDef ->
                            column
                                [ width fill
                                , spacing (scaled 4)
                                ]
                                [ viewModuleControls moduleNameString filterString viewType
                                , wrappedRow [ spacing (scaled 4) ]
                                    (accessControlledModuleDef.value.values
                                        |> Dict.toList
                                        |> List.filterMap
                                            (\( valueName, accessControlledValueDef ) ->
                                                let
                                                    matchesFilter =
                                                        case filterString of
                                                            Just filter ->
                                                                String.contains
                                                                    (filter |> String.toLower)
                                                                    (valueName
                                                                        |> Name.toHumanWords
                                                                        |> List.map String.toLower
                                                                        |> String.join " "
                                                                    )

                                                            Nothing ->
                                                                True

                                                    valueFQName =
                                                        ( packageName, moduleName, valueName )
                                                in
                                                if matchesFilter then
                                                    Just
                                                        (el [ alignTop ]
                                                            (viewAsCard
                                                                (column [ spacing 5 ]
                                                                    [ valueName
                                                                        |> Name.toHumanWords
                                                                        |> String.join " "
                                                                        |> text
                                                                    , viewArgumentEditors model valueFQName accessControlledValueDef.value
                                                                    ]
                                                                )
                                                                (case viewType of
                                                                    InsightView ->
                                                                        viewValue
                                                                            model
                                                                            distribution
                                                                            valueFQName
                                                                            accessControlledValueDef.value

                                                                    XRayView ->
                                                                        XRayView.viewValueDefinition XRayView.viewType accessControlledValueDef
                                                                )
                                                            )
                                                        )

                                                else
                                                    Nothing
                                            )
                                    )
                                ]

                        Nothing ->
                            text (String.join " " [ "Module", moduleNameString |> String.join ".", "not found" ])

                NotFound ->
                    text "Route not found"

                Function (( _, moduleName, localName ) as fQName) ->
                    let
                        references : IR
                        references =
                            IR.fromDistribution distribution

                        popupScreen : PopupScreenRecord
                        popupScreen =
                            { variableIndex = 0
                            , variableValue = Nothing
                            }

                        config : Config Msg
                        config =
                            { irContext =
                                { distribution = distribution
                                , references = Interpreter.referencesForDistribution distribution
                                }
                            , state =
                                { expandedFunctions = Dict.empty
                                , variables = Dict.empty
                                , popupVariables = popupScreen
                                , theme = Theme.fromConfig Nothing
                                }
                            , handlers =
                                { onReferenceClicked = ExpandReference
                                , onHoverOver = ExpandVariable
                                , onHoverLeave = ShrinkVariable
                                }
                            }

                        testCases : TestCases
                        testCases =
                            Dict.get fQName model.testSuite
                                |> Maybe.withDefault []

                        functionView : Element Msg
                        functionView =
                            Distribution.lookupValueDefinition (QName.fromName moduleName localName) distribution
                                |> Maybe.map
                                    (\valueDef ->
                                        viewValue model distribution fQName valueDef
                                    )
                                |> Maybe.withDefault (text (String.join " " [ "Module", [ moduleName |> Path.toString Name.toTitleCase "." ] |> String.join ".", "not found" ]))
                    in
                    Element.column [ padding 10, spacing 10 ]
                        [ Element.column [ spacing 10, padding 10 ]
                            [ el [ Font.bold, Font.size (scaled 2) ] (text "TestCases :")
                            , el [ centerY, centerX, width fill, height fill ] (viewTable config references testCases)
                            ]
                        , Element.column [ spacing 10, padding 10 ]
                            [ el [ Font.bold, Font.size (scaled 2) ] (text "Function :")
                            , el [ centerY, centerX ] functionView
                            ]

                        --viewAsCard (text "Function :") functionView
                        ]


viewTable : Config Msg -> IR -> TestCases -> Element Msg
viewTable config references testCases =
    Element.table [ centerY, centerX, width fill, height fill ]
        { data = testCases
        , columns =
            [ { header =
                    el
                        [ Border.width 2
                        , padding 5
                        , centerY
                        , centerX
                        , Font.bold
                        ]
                        (el [ centerY, centerX ] (text "Inputs"))
              , width = fill
              , view =
                    \testcase ->
                        el [ centerY, centerX, Border.widthEach { bottom = 2, top = 0, right = 2, left = 2 }, width fill, height fill ]
                            (viewInputTestCase config
                                references
                                (testcase.inputs
                                    |> Dict.toList
                                 --|> List.map (\( name, rawValue ) -> rawValue)
                                )
                            )
              }
            , { header =
                    el
                        [ Border.widthEach { bottom = 2, top = 2, right = 2, left = 0 }
                        , padding 5
                        , centerX
                        , centerY
                        , Font.bold
                        ]
                        (el [ centerY, centerX ] (text "Outputs"))
              , width = fill
              , view =
                    \testcase ->
                        el [ centerY, centerX, Border.widthEach { bottom = 2, top = 0, right = 2, left = 0 }, width fill, height fill ]
                            (viewOutputTestCase config references testcase.expectedOutput)
              }
            ]
        }


viewOutputTestCase : Config Msg -> IR -> RawValue -> Element Msg
viewOutputTestCase config references rawValue =
    case rawToVisualTypedValue references rawValue of
        Ok typedValue ->
            el [ centerX, centerY ] (ViewValue.viewValue config typedValue)

        Err error ->
            el [ centerX, centerY ] (text (Infer.typeErrorToMessage error))


viewInputTestCase : Config Msg -> IR -> List ( Name, RawValue ) -> Element Msg
viewInputTestCase config references rawValue =
    rawValue
        |> List.map
            (\( name, singleRawValue ) ->
                case rawToVisualTypedValue references singleRawValue of
                    Ok typedValue ->
                        column [ spacing 10, padding 5, centerX ]
                            [ el [ centerX, Font.bold ] (text (Name.toHumanWords name |> String.join ""))
                            , el [ centerX, centerY ] (ViewValue.viewValue config typedValue)
                            ]

                    Err error ->
                        el [] (text (Infer.typeErrorToMessage error))
            )
        |> row [ spacing 5, padding 5, centerX ]


viewArgumentEditors : Model -> FQName -> Value.Definition () (Type ()) -> Element Msg
viewArgumentEditors model fQName valueDef =
    valueDef.inputTypes
        |> List.map
            (\( argName, _, argType ) ->
                row
                    [ Background.color (rgb 1 1 1)
                    , Border.rounded 5
                    , spacing 10
                    ]
                    [ el [ paddingXY 10 0 ]
                        (text (argName |> Name.toHumanWords |> String.join " "))
                    , el []
                        (Edit.editValue
                            argType
                            (model.argState |> Dict.get fQName |> Maybe.andThen (Dict.get argName))
                            (ArgValueUpdated fQName argName)
                            (InvalidArgValue fQName argName)
                        )
                    ]
            )
        |> wrappedRow
            [ spacing 5
            ]


scaled : Int -> Int
scaled =
    Element.modular 10 1.25 >> round



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


viewModuleControls : List String -> Maybe String -> ViewType -> Element Msg
viewModuleControls moduleName filterString viewType =
    let
        viewTypeBackground expectedType =
            if viewType == expectedType then
                Background.color (rgb 0.8 0.8 0.8)

            else
                Background.color (rgb 1 1 1)
    in
    row
        [ width fill
        , spacing (scaled 2)
        , height shrink
        ]
        [ Input.text
            [ paddingXY 10 4
            , Border.width 1
            , Border.rounded 10
            ]
            { onChange = ValueFilterChanged
            , text = filterString |> Maybe.withDefault ""
            , placeholder = Just (Input.placeholder [] (text "start typing to filter values ..."))
            , label = labelHidden "filter values"
            }
        , el []
            (row [ spacing 5 ]
                [ link [ paddingXY 6 4, Border.rounded 3, viewTypeBackground XRayView ]
                    { url = makeURL moduleName filterString XRayView
                    , label = text "x-ray"
                    }
                , text "|"
                , link [ paddingXY 6 4, Border.rounded 3, viewTypeBackground InsightView ]
                    { url = makeURL moduleName filterString InsightView
                    , label = text "insight"
                    }
                ]
            )
        ]


makeURL : List String -> Maybe String -> ViewType -> String
makeURL moduleName filterString viewType =
    String.concat
        [ "/module/"
        , moduleName |> String.join "."
        , "?filter="
        , filterString |> Maybe.withDefault ""
        , "&view="
        , case viewType of
            InsightView ->
                "insight"

            _ ->
                "raw"
        ]


viewValue : Model -> Distribution -> FQName -> Value.Definition () (Type ()) -> Element Msg
viewValue model distribution valueFQName valueDef =
    let
        popupScreen : PopupScreenRecord
        popupScreen =
            { variableIndex = 0
            , variableValue = Nothing
            }

        validArgValues : Dict Name (Value () ())
        validArgValues =
            model.argState
                |> Dict.get valueFQName
                |> Maybe.withDefault Dict.empty

        config : Config Msg
        config =
            { irContext =
                { distribution = distribution
                , references = Interpreter.referencesForDistribution distribution
                }
            , state =
                { expandedFunctions = Dict.empty
                , variables = validArgValues
                , popupVariables = popupScreen
                , theme = Theme.fromConfig Nothing
                }
            , handlers =
                { onReferenceClicked = ExpandReference
                , onHoverOver = ExpandVariable
                , onHoverLeave = ShrinkVariable
                }
            }
    in
    ViewValue.viewDefinition config valueFQName valueDef


viewAsCard : Element msg -> Element msg -> Element msg
viewAsCard header content =
    let
        gray =
            rgb 0.9 0.9 0.9

        white =
            rgb 1 1 1
    in
    column
        [ Background.color gray
        , Border.rounded 3
        , height (shrink |> minimum 200)
        , width (shrink |> minimum 200)
        , padding 5
        , spacing 5
        ]
        [ el
            [ width fill
            , padding 2
            , Font.size (scaled 2)
            ]
            header
        , el
            [ Background.color white
            , Border.rounded 3
            , padding 5
            , height fill
            , width fill
            , scrollbars
            ]
            content
        ]


noBorderWidth =
    { top = 0
    , right = 0
    , bottom = 0
    , left = 0
    }
