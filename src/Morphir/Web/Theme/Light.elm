module Morphir.Web.Theme.Light exposing (..)

import Element exposing (el, padding, paddingXY, text)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Morphir.Web.Theme exposing (Theme)


theme : (Int -> Int) -> Theme msg
theme scaled =
    { button =
        \options ->
            Input.button
                [ Background.color orange
                , padding (scaled 1)
                , Border.rounded (scaled -2)
                , Font.size (scaled 2)
                , Font.bold
                ]
                { onPress = Just options.onPress
                , label = text options.label
                }
    , disabledButton =
        \label ->
            el
                [ Background.color gray
                , padding (scaled 1)
                , Border.rounded (scaled -2)
                , Font.size (scaled 2)
                , Font.bold
                ]
                (text label)
    , heading =
        \level label ->
            el
                [ Font.size (scaled (6 - level))
                , paddingXY 0 (scaled (3 - level))
                ]
                (text label)
    , highlightColor =
        blue
    }


blue =
    Element.rgb255 0 163 225


orange =
    Element.rgb255 255 105 0


gray =
    Element.rgb255 141 141 141


silver =
    Element.rgb255 192 192 192


black =
    Element.rgb255 0 0 0


white =
    Element.rgb255 255 255 255


green =
    Element.rgb255 100 180 100


red =
    Element.rgb255 180 100 100
