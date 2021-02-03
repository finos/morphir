module Morphir.Web.DevelopApp exposing (..)

import Browser
import Browser.Navigation as Nav
import Dict exposing (Dict)
import Element exposing (Element, alignTop, column, el, fill, height, image, layout, link, minimum, padding, paddingXY, px, rgb, row, shrink, spacing, text, width, wrappedRow)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input exposing (labelHidden)
import Http
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Distribution.Codec as DistributionCodec
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Visual.ViewValue as ViewValue
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
    | ExpandReference FQName Bool
    | ValueFilterChanged String


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
                            Nav.pushUrl model.key
                                (makeURL moduleName (Just filterString) viewType)

                        _ ->
                            Cmd.none
            in
            ( { model | route = newRoute }
            , cmd
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
    | Module (List String) (Maybe String) ViewType
    | NotFound


type ViewType
    = RawIRView
    | InsightView


viewTypeFromString : String -> ViewType
viewTypeFromString string =
    case string of
        "insight" ->
            InsightView

        _ ->
            RawIRView


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
                <?> (Query.string "view" |> Query.map (Maybe.map viewTypeFromString >> Maybe.withDefault RawIRView))
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
                , el [ padding 5 ] (viewBody model)
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
                    { src = "/assets/2020_Morphir_Logo_Icon_WHT.svg"
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
                    viewAsCard "Modules"
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

                Module moduleName filterString viewType ->
                    case packageDef.modules |> Dict.get (moduleName |> List.map Name.fromString) of
                        Just accessControlledModuleDef ->
                            column
                                [ spacing (scaled 4)
                                ]
                                [ viewModuleControls moduleName filterString viewType
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
                                                in
                                                if matchesFilter then
                                                    Just
                                                        (el [ alignTop ]
                                                            (viewAsCard
                                                                (valueName
                                                                    |> Name.toHumanWords
                                                                    |> String.join " "
                                                                )
                                                                (case viewType of
                                                                    InsightView ->
                                                                        viewValue
                                                                            distribution
                                                                            accessControlledValueDef.value
                                                                            Dict.empty

                                                                    RawIRView ->
                                                                        XRayView.viewValueDefinition accessControlledValueDef
                                                                )
                                                            )
                                                        )

                                                else
                                                    Nothing
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
            [ padding 4
            ]
            { onChange = ValueFilterChanged
            , text = filterString |> Maybe.withDefault ""
            , placeholder = Just (Input.placeholder [] (text "start typing to filter values ..."))
            , label = labelHidden "filter values"
            }
        , el []
            (row [ spacing 5 ]
                [ link [ paddingXY 6 4, Border.rounded 3, viewTypeBackground RawIRView ]
                    { url = makeURL moduleName filterString RawIRView
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


viewAsCard : String -> Element msg -> Element msg
viewAsCard title content =
    let
        gray =
            rgb 0.9 0.9 0.9
    in
    column
        [ Border.width 3
        , Border.color gray
        , Border.rounded 3
        , height (shrink |> minimum 200)
        , width (shrink |> minimum 200)
        ]
        [ el
            [ width fill
            , padding 5
            , Background.color gray
            , Font.size (scaled 3)
            ]
            (text title)
        , el [ padding 5 ] content
        ]


noBorderWidth =
    { top = 0
    , right = 0
    , bottom = 0
    , left = 0
    }
