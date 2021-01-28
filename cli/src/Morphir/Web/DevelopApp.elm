module Morphir.Web.DevelopApp exposing (..)

import Browser
import Browser.Navigation as Nav
import Dict exposing (Dict)
import Element exposing (Element, column, el, fill, height, image, layout, link, padding, paddingEach, paddingXY, px, row, spacing, text, width)
import Element.Background as Background
import Element.Font as Font
import Http
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Distribution.Codec as DistributionCodec
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Value.Interpreter exposing (FQN)
import Morphir.Visual.ViewValue as ViewValue
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
    , irState : IRState
    , serverState : ServerState
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
      }
    , httpMakeModel
    )



-- UPDATE


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | HttpError Http.Error
    | ServerGetIRResponse Distribution
    | ExpandReference FQN Bool


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

        HttpError httpError ->
            ( { model | serverState = ServerHttpError httpError }
            , Cmd.none
            )

        ServerGetIRResponse distribution ->
            ( { model | irState = IRLoaded distribution }
            , Cmd.none
            )

        ExpandReference fqn bool ->
            ( model, Cmd.none )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- ROUTE


type Route
    = Home
    | Module (List String)
    | NotFound


routeParser : UrlParser.Parser (Route -> a) a
routeParser =
    UrlParser.oneOf
        [ UrlParser.map Home UrlParser.top
        , UrlParser.map Module (UrlParser.string |> UrlParser.map (String.split "."))
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
                , viewBody model
                ]
            )
        ]
    }


viewTitle : Model -> String
viewTitle model =
    case model.route of
        Home ->
            "Morphir - Home"

        Module moduleName ->
            "Morphir - " ++ (moduleName |> String.join " / ")

        NotFound ->
            "Morphir - Not Found"


viewHeader : Model -> Element Msg
viewHeader model =
    column
        [ width fill
        , Background.color model.theme.highlightColor
        , padding 5
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
        ]


viewBody : Model -> Element Msg
viewBody model =
    case model.irState of
        IRLoading ->
            text "Loading the IR ..."

        IRLoaded distribution ->
            let
                packageDef =
                    case distribution of
                        Library _ _ pack ->
                            pack
            in
            case model.route of
                Home ->
                    column
                        [ padding 10
                        , spacing 10
                        ]
                        (packageDef.modules
                            |> Dict.toList
                            |> List.map
                                (\( moduleName, accessControlledModuleDef ) ->
                                    link [ Font.size 18 ]
                                        { url =
                                            "/" ++ (moduleName |> List.map Name.toTitleCase |> String.join ".")
                                        , label =
                                            moduleName
                                                |> List.map (Name.toHumanWords >> String.join " ")
                                                |> String.join " / "
                                                |> text
                                        }
                                )
                        )

                Module moduleName ->
                    case packageDef.modules |> Dict.get (moduleName |> List.map Name.fromString) of
                        Just accessControlledModuleDef ->
                            column
                                [ padding 10
                                , spacing 30
                                ]
                                [ link [ Font.size 18 ]
                                    { url =
                                        "/"
                                    , label = text "< Back to modules"
                                    }
                                , column [ spacing 30 ]
                                    (accessControlledModuleDef.value.values
                                        |> Dict.toList
                                        |> List.concatMap
                                            (\( valueName, accessControlledValueDef ) ->
                                                [ el [ Font.size 18 ]
                                                    (valueName
                                                        |> Name.toHumanWords
                                                        |> String.join " "
                                                        |> text
                                                    )
                                                , el
                                                    [ paddingEach { left = 20, right = 0, top = 0, bottom = 0 }
                                                    ]
                                                    (viewValue
                                                        distribution
                                                        accessControlledValueDef.value
                                                        Dict.empty
                                                    )
                                                ]
                                            )
                                    )
                                ]

                        Nothing ->
                            text (String.join " " [ "Module", moduleName |> String.join ".", "not found" ])

                NotFound ->
                    text "Route not found"


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
                DistributionCodec.decodeDistribution
        }


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
    ViewValue.viewDefinition distribution valueDef validArgValues ExpandReference Dict.empty
