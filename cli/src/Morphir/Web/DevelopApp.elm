module Morphir.Web.DevelopApp exposing (..)

import Browser
import Browser.Navigation as Nav
import Element exposing (Element, column, el, fill, height, image, layout, link, padding, paddingXY, px, rgb, row, spacing, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Html exposing (Html, a, b, li, text, ul)
import Morphir.Web.Theme exposing (Theme)
import Morphir.Web.Theme.Light as Light
import Url exposing (Url)
import Url.Parser as UrlParser



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
    }


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    ( { key = key
      , route = toRoute url
      , theme = Light.theme scaled
      }
    , Cmd.none
    )



-- UPDATE


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
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



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- ROUTE


type Route
    = Stats
    | Insight
    | NotFound


routeParser : UrlParser.Parser (Route -> a) a
routeParser =
    UrlParser.oneOf
        [ UrlParser.map Stats (UrlParser.s "stats")
        , UrlParser.map Insight (UrlParser.s "insight")
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
            [ width fill
            ]
            (column
                [ width fill
                ]
                [ viewHeader model
                ]
            )
        ]
    }


viewTitle : Model -> String
viewTitle model =
    case model.route of
        Stats ->
            "Morphir - Stats"

        Insight ->
            "Morphir - Insight"

        NotFound ->
            "Morphir"


viewHeader : Model -> Element Msg
viewHeader model =
    let
        menuItems =
            [ ( Stats, "/stats" )
            , ( Insight, "/insight" )
            ]
    in
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
                [ image
                    [ height (px 50)
                    ]
                    { src = "assets/2020_Morphir_Logo_Icon_WHT.svg"
                    , description = "Morphir Logo"
                    }
                , el [ paddingXY 10 0 ]
                    (model.theme.heading 1 "Morphir Development Server")
                ]
            ]
        , row []
            (menuItems
                |> List.map
                    (\( route, url ) ->
                        let
                            fontColor =
                                if route == model.route then
                                    rgb 0 0 0

                                else
                                    rgb 1 1 1

                            backgroundColor =
                                if route == model.route then
                                    rgb 1 1 1

                                else
                                    model.theme.highlightColor
                        in
                        link
                            [ Font.color fontColor
                            , Background.color backgroundColor
                            , paddingXY 20 5
                            , Border.roundEach { topLeft = 5, topRight = 5, bottomLeft = 0, bottomRight = 0 }
                            ]
                            { url = url
                            , label = Debug.toString route |> Element.text
                            }
                    )
            )
        ]


scaled : Int -> Int
scaled =
    Element.modular 12 1.25 >> round
