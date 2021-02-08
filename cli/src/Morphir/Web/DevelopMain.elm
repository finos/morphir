module Morphir.Web.DevelopMain exposing (Model(..), Msg(..), distributionDecoder, init, main, makeModel, scaled, subscriptions, theme, update, view, viewResult, viewValueSelection)

import Browser
import Dict exposing (Dict)
import Element exposing (Color, Element, column, el, fill, height, html, image, padding, paddingXY, px, rgb255, row, spacing, text, width, wrappedRow)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Http
import Json.Decode as Decode exposing (Decoder, string)
import Morphir.Compiler as Compiler
import Morphir.IR.AccessControlled exposing (AccessControlled)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.Distribution.Codec as DistributionCodec
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.QName as QName exposing (QName(..))
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, Value)
import Morphir.Visual.Components.VisualizationState exposing (VisualizationState)
import Morphir.Visual.Edit as Edit
import Morphir.Visual.ViewValue as ViewValue
import Morphir.Web.Theme exposing (Theme)
import Morphir.Web.Theme.Light as Light exposing (blue)



-- MAIN


main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }



-- MODEL


type Model
    = HttpFailure Http.Error
    | WaitingForResponse
    | MakeComplete (Result (List Compiler.Error) Distribution)
    | FunctionSelected VisualizationState


init : () -> ( Model, Cmd Msg )
init _ =
    ( WaitingForResponse, makeModel )



-- UPDATE


type Msg
    = Make
    | MakeResult (Result Http.Error (Result (List Compiler.Error) Distribution))
    | SelectFunction String
    | UpdateArgumentValue Int (Value () ())
    | InvalidArgumentValue Int String
    | ExpandReference FQName Bool


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        getDistribution : Maybe Distribution
        getDistribution =
            case model of
                MakeComplete result ->
                    result |> Result.toMaybe

                FunctionSelected visualizationState ->
                    Just visualizationState.distribution

                _ ->
                    Nothing
    in
    case msg of
        Make ->
            ( WaitingForResponse, makeModel )

        MakeResult result ->
            case result of
                Ok distributionResult ->
                    ( MakeComplete distributionResult, Cmd.none )

                Err error ->
                    ( HttpFailure error, Cmd.none )

        SelectFunction valueID ->
            valueID
                |> QName.fromString
                |> Maybe.andThen
                    (\qName ->
                        getDistribution
                            |> Maybe.andThen
                                (\distribution ->
                                    distribution
                                        |> Distribution.lookupValueDefinition qName
                                        |> Maybe.map
                                            (\valueDef ->
                                                FunctionSelected
                                                    { distribution = distribution
                                                    , selectedFunction = qName
                                                    , functionDefinition = valueDef
                                                    , functionArguments = []
                                                    , expandedFunctions = Dict.empty
                                                    }
                                            )
                                )
                            |> Maybe.map (\m -> ( m, Cmd.none ))
                    )
                |> Maybe.withDefault ( model, Cmd.none )

        UpdateArgumentValue argIndex argValue ->
            case model of
                FunctionSelected visualizationState ->
                    ( FunctionSelected
                        { visualizationState
                            | functionArguments =
                                List.indexedMap
                                    (\index value ->
                                        if index == argIndex then
                                            argValue

                                        else
                                            value
                                    )
                                    visualizationState.functionArguments
                        }
                    , Cmd.none
                    )

                --( FunctionSelected { visualizationState | functionArguments = visualizationState.functionArguments |> Dict.insert argName (Ok argValue) }
                --, Cmd.none
                --)
                _ ->
                    ( model, Cmd.none )

        InvalidArgumentValue argName message ->
            --case model of
            --    FunctionSelected visualizationState ->
            --        ( FunctionSelected visualizationState (funArgs |> Dict.insert argName (Err message))
            --        , Cmd.none
            --        )
            ( model, Cmd.none )

        ExpandReference (( packageName, moduleName, localName ) as fqName) bool ->
            case model of
                FunctionSelected visualizationState ->
                    if visualizationState.expandedFunctions |> Dict.member fqName then
                        case bool of
                            True ->
                                ( FunctionSelected { visualizationState | expandedFunctions = visualizationState.expandedFunctions |> Dict.remove fqName }, Cmd.none )

                            False ->
                                ( model, Cmd.none )

                    else
                        ( FunctionSelected
                            { visualizationState
                                | expandedFunctions =
                                    Distribution.lookupValueDefinition (QName moduleName localName) visualizationState.distribution
                                        |> Maybe.map (\valueDef -> visualizationState.expandedFunctions |> Dict.insert fqName valueDef)
                                        |> Maybe.withDefault visualizationState.expandedFunctions
                            }
                        , Cmd.none
                        )

                _ ->
                    ( model, Cmd.none )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none



-- VIEW


view : Model -> Html Msg
view model =
    Element.layoutWith
        { options =
            []
        }
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
        (column [ width fill ]
            [ row
                [ width fill
                , padding 10
                , Background.color blue
                ]
                [ row
                    [ width fill
                    ]
                    [ image
                        [ height (px 50)
                        ]
                        { src = "assets/2020_Morphir_Logo_Icon_WHT.svg"
                        , description = "Morphir Logo"
                        }
                    , el [ paddingXY 10 0 ]
                        (theme.heading 1 "Morphir Development Server")
                    ]
                , case model of
                    WaitingForResponse ->
                        theme.disabledButton "Loading ..."

                    _ ->
                        theme.button
                            { onPress = Make
                            , label = "Reload"
                            }
                ]
            , el
                [ width fill
                , padding 10
                ]
                (viewResult model)
            ]
        )


scaled : Int -> Int
scaled =
    Element.modular 12 1.25 >> round


theme : Theme Msg
theme =
    Light.theme scaled


viewResult : Model -> Element Msg
viewResult model =
    case model of
        HttpFailure error ->
            let
                message =
                    case error of
                        Http.BadUrl string ->
                            "Bad URL was supplied: " ++ string

                        Http.Timeout ->
                            "Request timed out!"

                        Http.NetworkError ->
                            "Network error!"

                        Http.BadStatus int ->
                            "Request failed with error code " ++ String.fromInt int

                        Http.BadBody string ->
                            "Error while decoding response body: " ++ string
            in
            column []
                [ text message
                ]

        WaitingForResponse ->
            text "Running morphir make  ..."

        MakeComplete distributionResult ->
            case distributionResult of
                Ok distribution ->
                    column [ spacing 20 ]
                        [ el [ Font.size 18 ] (text "Function to visualize: ")
                        , viewValueSelection distribution
                        ]

                Err error ->
                    text ("Error: " ++ Debug.toString error)

        FunctionSelected visualizationState ->
            column [ spacing 20 ]
                [ el [ Font.size 18 ] (text "Function to visualize: ")
                , viewValueSelection visualizationState.distribution
                , el [ Font.size 18 ] (text "Arguments: ")
                , viewArgumentEditors visualizationState.functionDefinition visualizationState.functionArguments
                , el [ Font.size 18 ] (text "Visualization: ")
                , viewValue visualizationState
                ]


viewValueSelection : Distribution -> Element Msg
viewValueSelection distro =
    case distro of
        Distribution.Library packageName dependencies packageDefinition ->
            let
                options : List (Html Msg)
                options =
                    packageDefinition.modules
                        |> Dict.toList
                        |> List.concatMap
                            (\( moduleName, accessControlledModuleDef ) ->
                                accessControlledModuleDef.value.values
                                    |> Dict.toList
                                    |> List.map
                                        (\( valueName, valueDef ) ->
                                            let
                                                valueID =
                                                    QName.fromName moduleName valueName
                                                        |> QName.toString

                                                valueNameText =
                                                    String.join "."
                                                        [ Path.toString Name.toTitleCase "." moduleName
                                                        , Name.toCamelCase valueName
                                                        ]
                                            in
                                            Html.option
                                                [ Html.Attributes.value valueID
                                                ]
                                                [ Html.text valueNameText
                                                ]
                                        )
                            )
            in
            column [ width fill ]
                [ html
                    (Html.select
                        [ Html.Events.on "change" (Decode.field "target" (Decode.field "value" Decode.string) |> Decode.map SelectFunction)
                        ]
                        options
                    )
                ]


viewArgumentEditors : Value.Definition () (Type ()) -> List (Value () ()) -> Element Msg
viewArgumentEditors valueDef argValues =
    wrappedRow [ spacing 20 ]
        (valueDef.inputTypes
            |> List.indexedMap
                (\index ( argName, va, argType ) ->
                    column
                        [ spacing 5
                        , padding 5
                        , Border.width 1
                        , Border.color (rgb255 100 100 100)
                        ]
                        [ el [] (text (String.concat [ argName |> Name.toHumanWords |> String.join " ", ": " ]))
                        , el []
                            (html
                                (Edit.editValue argType
                                    (UpdateArgumentValue index)
                                    (InvalidArgumentValue index)
                                )
                            )
                        ]
                )
        )


viewValue : VisualizationState -> Element Msg
viewValue visualizationState =
    let
        validArgValues : Dict Name (Value () ())
        validArgValues =
            List.map2
                (\( argName, _, _ ) argValue ->
                    ( argName, argValue )
                )
                visualizationState.functionDefinition.inputTypes
                visualizationState.functionArguments
                |> Dict.fromList
    in
    ViewValue.viewDefinition visualizationState.distribution visualizationState.functionDefinition validArgValues ExpandReference visualizationState.expandedFunctions



-- HTTP


makeModel : Cmd Msg
makeModel =
    Http.get
        { url = "/server/make"
        , expect = Http.expectJson MakeResult distributionDecoder
        }


distributionDecoder : Decoder (Result (List Compiler.Error) Distribution)
distributionDecoder =
    Decode.index 0 Decode.string
        |> Decode.andThen
            (\tag ->
                case tag of
                    "ok" ->
                        Decode.index 1 DistributionCodec.decodeDistribution
                            |> Decode.map Ok

                    "err" ->
                        Decode.index 1 (Decode.succeed [])
                            |> Decode.map Err

                    other ->
                        Decode.fail ("Unexpected Result tag: " ++ other)
            )
