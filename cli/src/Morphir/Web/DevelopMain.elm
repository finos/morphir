module Morphir.Web.DevelopMain exposing (..)

import Browser
import Dict
import Element exposing (Element, column, el, fill, height, image, padding, paragraph, px, row, text, width)
import Element.Background as Background
import Element.Font as Font
import Html exposing (Html)
import Http
import Json.Decode as Decode exposing (Decoder, field, string)
import Morphir.Elm.CLI as CLI
import Morphir.IR.AccessControlled exposing (AccessControlled)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.Distribution.Codec as DistributionCodec
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
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
    | MakeComplete (Result CLI.Error Distribution)


init : () -> ( Model, Cmd Msg )
init _ =
    ( WaitingForResponse, makeModel )



-- UPDATE


type Msg
    = Make
    | MakeResult (Result Http.Error (Result CLI.Error Distribution))


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Make ->
            ( WaitingForResponse, makeModel )

        MakeResult result ->
            case result of
                Ok distributionResult ->
                    ( MakeComplete distributionResult, Cmd.none )

                Err error ->
                    ( HttpFailure error, Cmd.none )



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
                , Background.color blue
                ]
                [ row
                    [ padding 10
                    , width fill
                    ]
                    [ image
                        [ height (px 60)
                        ]
                        { src = "assets/2020_Morphir_Logo_Horizontal_WHT.svg"
                        , description = "Morphir"
                        }
                    , theme.heading 3 "Development Server"
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
            , viewResult model
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
                    viewDistribution distribution

                Err error ->
                    text ("Error: " ++ Debug.toString error)


viewDistribution : Distribution -> Element Msg
viewDistribution distro =
    case distro of
        Distribution.Library packageName dependencies packageDefinition ->
            column []
                [ text
                    (String.join " "
                        [ "Package:"
                        , packageName |> Path.toList |> List.map (Name.toHumanWords >> String.join " ") |> String.join " / "
                        ]
                    )
                , theme.heading 1 "Modules"
                , column []
                    (packageDefinition.modules
                        |> Dict.toList
                        |> List.map
                            (\( moduleName, moduleDef ) ->
                                column []
                                    [ text (moduleName |> Path.toList |> List.map (Name.toHumanWords >> String.join " ") |> String.join " / ")
                                    , viewModule moduleDef
                                    ]
                            )
                    )
                ]


viewModule : AccessControlled (Module.Definition ta va) -> Element Msg
viewModule moduleDef =
    paragraph []
        [--text (Debug.toString moduleDef)
        ]



-- HTTP


makeModel : Cmd Msg
makeModel =
    Http.get
        { url = "/server/make"
        , expect = Http.expectJson MakeResult distributionDecoder
        }


distributionDecoder : Decoder (Result CLI.Error Distribution)
distributionDecoder =
    Decode.index 0 Decode.string
        |> Decode.andThen
            (\tag ->
                case tag of
                    "ok" ->
                        Decode.index 1 DistributionCodec.decodeDistribution
                            |> Decode.map Ok

                    "err" ->
                        Decode.index 1 CLI.decodeError
                            |> Decode.map Err

                    other ->
                        Decode.fail ("Unexpected Result tag: " ++ other)
            )
