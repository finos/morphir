module Morphir.Visual.Common exposing (colorToSvg, cssClass, element, grayScale, nameToText, nameToTitleText, pathToDisplayString, pathToFullUrl, pathToTitleText, pathToUrl, tooltip)

import Element exposing (Attribute, Color, Element, el, fill, height, htmlAttribute, inFront, mouseOver, none, rgb, shrink, transparent, width)
import Html exposing (Html)
import Html.Attributes exposing (class)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path exposing (Path)


cssClass : String -> Attribute msg
cssClass className =
    Element.htmlAttribute (class className)


nameToText : Name -> String
nameToText name =
    name
        |> Name.toHumanWords
        |> String.join " "


nameToTitleText : Name -> String
nameToTitleText name =
    name
        |> Name.toHumanWords
        |> List.map (\word -> Name.toTitleCase [ word ])
        |> String.join " "


pathToTitleText : Path -> String
pathToTitleText path =
    path
        |> List.map nameToTitleText
        |> String.join " - "


element : Element msg -> Html msg
element elem =
    Element.layoutWith
        { options =
            [ Element.noStaticStyleSheet
            ]
        }
        [ width shrink
        , height shrink
        ]
        elem


grayScale : Float -> Color
grayScale v =
    rgb v v v


pathToUrl : Path -> String
pathToUrl path =
    "/" ++ Path.toString Name.toTitleCase "." path


pathToFullUrl : List Path -> String
pathToFullUrl path =
    "/home" ++ String.concat (List.map pathToUrl path)


pathToDisplayString : Path -> String
pathToDisplayString =
    Path.toString (Name.toHumanWords >> String.join " ") " > "


tooltip : (Element msg -> Attribute msg) -> Element msg -> Attribute msg
tooltip usher tooltip_ =
    inFront <|
        el
            [ width fill
            , height fill
            , transparent True
            , mouseOver [ transparent False ]
            , usher <|
                el [ htmlAttribute (Html.Attributes.style "pointerEvents" "none") ]
                    tooltip_
            ]
            none


colorToSvg : Color -> String
colorToSvg color =
    let
        to255 : Float -> Int
        to255 f =
            round (255 * f)

        rgba =
            Element.toRgb color
    in
    String.concat
        [ "rgba("
        , rgba.red |> to255 |> String.fromInt
        , ", "
        , rgba.green |> to255 |> String.fromInt
        , ", "
        , rgba.blue |> to255 |> String.fromInt
        , ", "
        , rgba.alpha |> String.fromFloat
        , ")"
        ]
