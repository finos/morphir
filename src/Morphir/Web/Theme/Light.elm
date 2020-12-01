module Morphir.Web.Theme.Light exposing (..)

import Element exposing (el, padding, text)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Morphir.Web.Theme exposing (Theme)


theme : Theme msg
theme =
    { button =
        \options ->
            Input.button
                [ Background.color blue
                , padding 10
                , Border.rounded 5
                , Font.size 12
                , Font.bold
                ]
                { onPress = Just options.onPress
                , label = text options.label
                }
    , disabledButton =
        \label ->
            el
                [ Background.color gray
                , padding 10
                , Border.rounded 5
                , Font.size 12
                , Font.bold
                ]
                (text label)
    }


blue =
    Element.rgb255 0 163 225


orange =
    Element.rgb255 255 105 0


gray =
    Element.rgb255 141 141 141
