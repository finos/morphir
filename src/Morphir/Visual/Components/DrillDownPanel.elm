module Morphir.Visual.Components.DrillDownPanel exposing (..)

import Bootstrap.Accordion exposing (isOpen)
import Element exposing (Element, column, el, fill, padding, pointer, row, text, width, text, spacing)
import Element.Font as Font 
import Element.Border as Border
import Element.Events exposing (onClick)
import Morphir.Visual.Theme exposing (borderRounded)


type alias PanelConfig msg =
    { openMsg : msg
    , closeMsg : msg
    }


type alias Depth =
    Int


drillDownPanel : PanelConfig msg -> Depth -> Element msg -> Element msg -> Bool -> Element msg
drillDownPanel config depth headerElement openElement isOpen =
    let
        depthColor =
            let
                depthRgb =
                    1 - (0.1 * (toFloat <| depth + 1))
            in
            Element.fromRgb
                { red = depthRgb
                , green = depthRgb
                , blue = depthRgb
                , alpha = 1
                }
    in
    if isOpen then
        column [ borderRounded, Border.width 1, Border.color depthColor, padding <| (depth + 1) * 5, Border.innerGlow depthColor (toFloat depth + 3), spacing 10 ]
            [ el [ width fill, pointer, onClick config.closeMsg, Font.size 9, Font.bold ] (text "[ X ]")
            , el [width fill] openElement
            ]

    else
        row [ width fill, pointer, onClick config.openMsg ] [ headerElement ]
