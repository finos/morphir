module Morphir.Web.DevelopMain exposing (Model(..), Msg(..), distributionDecoder, init, main, makeModel, scaled, subscriptions, theme, update, view, viewResult, viewValueSelection)

import Browser
import Dict exposing (Dict)
import Element exposing (Element, column, el, fill, height, html, image, none, padding, paddingXY, paragraph, px, rgb255, row, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Http
import Json.Decode as Decode exposing (Decoder, field, string)
import Morphir.Compiler as Compiler
import Morphir.Elm.CLI as CLI
import Morphir.IR.AccessControlled exposing (AccessControlled)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.Distribution.Codec as DistributionCodec
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.QName as QName exposing (QName)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
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
    | FunctionSelected Distribution QName (Value.Definition () (Type ())) (Dict Name (Result String (Value () ())))


init : () -> ( Model, Cmd Msg )
init _ =
    ( WaitingForResponse, makeModel )



-- UPDATE


type Msg
    = Make
    | MakeResult (Result Http.Error (Result (List Compiler.Error) Distribution))
    | SelectFunction String
    | UpdateArgumentValue Name (Value () ())
    | InvalidArgumentValue Name String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        getDistribution : Maybe Distribution
        getDistribution =
            case model of
                MakeComplete result ->
                    result |> Result.toMaybe

                FunctionSelected distribution _ _ _ ->
                    Just distribution

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
                                        |> Maybe.map (\valueDef -> FunctionSelected distribution qName valueDef Dict.empty)
                                )
                            |> Maybe.map (\m -> ( m, Cmd.none ))
                    )
                |> Maybe.withDefault ( model, Cmd.none )

        UpdateArgumentValue argName argValue ->
            case model of
                FunctionSelected distribution qName valueDef argValues ->
                    ( FunctionSelected distribution qName valueDef (argValues |> Dict.insert argName (Ok argValue))
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        InvalidArgumentValue argName message ->
            case model of
                FunctionSelected distribution qName valueDef argValues ->
                    ( FunctionSelected distribution qName valueDef (argValues |> Dict.insert argName (Err message))
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
                    viewValueSelection distribution

                Err error ->
                    text ("Error: " ++ Debug.toString error)

        FunctionSelected distribution qName valueDef argValues ->
            column [ spacing 20 ]
                [ viewValueSelection distribution
                , viewArgumentEditors valueDef argValues
                , viewValue distribution valueDef argValues
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


viewArgumentEditors : Value.Definition () (Type ()) -> Dict Name (Result String (Value () ())) -> Element Msg
viewArgumentEditors valueDef argValues =
    column [ spacing 10 ]
        (valueDef.inputTypes
            |> List.map
                (\( argName, va, argType ) ->
                    column
                        [ spacing 3 ]
                        [ text (String.concat [ argName |> Name.toCamelCase, " : " ])
                        , html
                            (Edit.editValue argType
                                (UpdateArgumentValue argName)
                                (InvalidArgumentValue argName)
                            )
                        , text
                            (argValues
                                |> Dict.get argName
                                |> Maybe.map Debug.toString
                                |> Maybe.withDefault "not set"
                            )
                        ]
                )
        )


viewValue : Distribution -> Value.Definition () (Type ()) -> Dict Name (Result String (Value () ())) -> Element Msg
viewValue distribution valueDef argValues =
    let
        validArgValues : Dict Name (Value () ())
        validArgValues =
            argValues
                |> Dict.toList
                |> List.filterMap
                    (\( argName, argValueResult ) ->
                        argValueResult
                            |> Result.toMaybe
                            |> Maybe.map (Tuple.pair argName)
                    )
                |> Dict.fromList
    in
    if Dict.size argValues == List.length valueDef.inputTypes && Dict.size argValues == Dict.size validArgValues then
        ViewValue.viewWithData distribution valueDef validArgValues

    else
        ViewValue.view valueDef.body



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
