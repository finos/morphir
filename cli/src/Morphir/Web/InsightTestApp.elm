module Morphir.Web.InsightTestApp exposing (..)

import Browser
import Dict exposing (Dict)
import Element exposing (Element, column, el, fill, layout, none, padding, rgb, row, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import FontAwesome.Styles as Icon
import Html exposing (Html)
import Http
import Morphir.Correctness.Codec exposing (decodeTestSuite)
import Morphir.Correctness.Test exposing (TestCases, TestSuite)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.FormatVersion.Codec as DistributionCodec
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.SDK as SDK
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, TypedValue)
import Morphir.Visual.Config exposing (DrillDownFunctions(..))
import Morphir.Visual.Theme as Theme
import Morphir.Visual.ViewValue as ViewValue


main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }


type alias Flags =
    {}


type Model
    = LoadingDistribution
    | LoadingTests Distribution
    | Initialized Distribution TestSuite
    | Errored String


type Msg
    = HttpError Http.Error
    | HttpGetDistributionResponse Distribution
    | HttpGetTestsResponse TestSuite
    | DoNothing


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( LoadingDistribution
    , Cmd.batch [ httpGetDistribution ]
    )


httpGetDistribution : Cmd Msg
httpGetDistribution =
    Http.get
        { url = "/server/morphir-ir.json"
        , expect =
            Http.expectJson
                (\response ->
                    case response of
                        Err httpError ->
                            HttpError httpError

                        Ok result ->
                            HttpGetDistributionResponse result
                )
                DistributionCodec.decodeVersionedDistribution
        }


httpGetTestModel : Distribution -> Cmd Msg
httpGetTestModel ir =
    Http.get
        { url = "/server/morphir-tests.json"
        , expect =
            Http.expectJson
                (\response ->
                    case response of
                        Err httpError ->
                            HttpError httpError

                        Ok result ->
                            HttpGetTestsResponse result
                )
                (decodeTestSuite ir)
        }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        DoNothing ->
            ( model, Cmd.none )

        _ ->
            case ( model, msg ) of
                ( LoadingDistribution, HttpGetDistributionResponse distro ) ->
                    ( LoadingTests distro, httpGetTestModel distro )

                ( LoadingDistribution, HttpError error ) ->
                    ( Errored "Error while loading distribution", Cmd.none )

                ( LoadingTests distro, HttpGetTestsResponse testSuite ) ->
                    ( Initialized distro testSuite, Cmd.none )

                ( LoadingTests distro, HttpError error ) ->
                    ( Errored "Error while loading tests", Cmd.none )

                _ ->
                    ( Errored "Invalid state transition.", Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none


view : Model -> Html Msg
view model =
    Html.div []
        [ Icon.css
        , layout
            [ Font.size 12
            , padding 10
            , Background.color (rgb 0.85 0.9 0.95)
            ]
            (viewModel model)
        ]


viewModel : Model -> Element Msg
viewModel model =
    case model of
        LoadingDistribution ->
            text "Loading distribution ..."

        LoadingTests _ ->
            text "Loading tests ..."

        Initialized distro testSuite ->
            viewInitialized distro testSuite

        Errored string ->
            text string


viewInitialized : Distribution -> TestSuite -> Element Msg
viewInitialized distro testSuite =
    testSuite
        |> Dict.toList
        |> List.filterMap
            (\( fqn, testCases ) ->
                distro
                    |> Distribution.lookupValueDefinition fqn
                    |> Maybe.map
                        (\valueDef ->
                            viewValue distro fqn valueDef testCases
                        )
            )
        |> column [ spacing 10 ]


viewValue : Distribution -> FQName -> Value.Definition () (Type ()) -> TestCases -> Element Msg
viewValue distro (( _, moduleName, localName ) as fqn) valueDefinition testCases =
    let
        cardColor : Element.Color
        cardColor =
            rgb 0.6 0.7 0.8

        functionBreadcrumbText : String
        functionBreadcrumbText =
            String.concat
                [ moduleName |> List.map (Name.toHumanWordsTitle >> String.join " ") |> String.join " ▸ "
                , " ▸ "
                , localName |> Name.toHumanWords |> String.join " "
                ]

        viewCase : String -> List (Maybe RawValue) -> Element Msg
        viewCase desc inputs =
            column []
                [ el
                    [ Font.size 14
                    , Font.bold
                    , Background.color cardColor
                    , padding 10
                    ]
                    (text desc)
                , el
                    [ width fill
                    , Border.width 5
                    , Border.color cardColor
                    , padding 10
                    , Background.color (rgb 1 1 1)
                    ]
                    (viewInsight distro
                        fqn
                        valueDefinition
                        inputs
                    )
                ]

        defaultCase : Element Msg
        defaultCase =
            viewCase functionBreadcrumbText []

        viewCases : List (Element Msg)
        viewCases =
            testCases
                |> List.indexedMap
                    (\index testCase ->
                        let
                            id =
                                String.concat
                                    [ functionBreadcrumbText
                                    , " ▸ Test Case "
                                    , String.fromInt (index + 1)
                                    ]

                            desc =
                                if testCase.description == "" then
                                    id

                                else
                                    id ++ ": " ++ testCase.description
                        in
                        viewCase desc testCase.inputs
                    )
                |> (::) defaultCase
    in
    column
        [ spacing 10 ]
        viewCases


viewInsight : Distribution -> FQName -> Value.Definition () (Type ()) -> List (Maybe RawValue) -> Element Msg
viewInsight distro fqn valueDef argValues =
    let
        variables : Dict Name RawValue
        variables =
            List.map2
                (\( argName, _, _ ) maybeArgValue ->
                    maybeArgValue
                        |> Maybe.map (Tuple.pair argName)
                )
                valueDef.inputTypes
                argValues
                |> List.filterMap identity
                |> Dict.fromList

        config =
            { ir = distro
            , nativeFunctions = SDK.nativeFunctions
            , state =
                { drillDownFunctions = DrillDownFunctions Dict.empty
                , variables = variables
                , nonEvaluatedVariables = Dict.empty
                , popupVariables =
                    { variableIndex = -1
                    , variableValue = Nothing
                    , nodePath = []
                    }
                , theme = Theme.fromConfig Nothing
                , highlightState = Nothing
                , zIndex = 9999
                }
            , handlers =
                { onReferenceClicked = \_ _ _ -> DoNothing
                , onReferenceClose = \_ _ _ -> DoNothing
                , onHoverOver = \_ _ _ -> DoNothing
                , onHoverLeave = \_ _ -> DoNothing
                }
            , nodePath = []
            }
    in
    ViewValue.viewDefinition config fqn valueDef
