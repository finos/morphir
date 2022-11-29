module Morphir.Visual.Components.DrillDownPanel exposing (..)

import Element exposing (Element, column, el, fill, padding, pointer, row, text, width)
import Element.Border as Border
import Element.Events exposing (onClick)
import Element.Font as Font
import Morphir.Visual.Theme exposing (Theme, borderRounded)
import Element exposing (Attribute)
import Html.Events
import Json.Decode as Decode


type alias PanelConfig msg =
    { openMsg : msg
    , closeMsg : msg
    , depth : Depth
    , closedElement : Element msg
    , openHeader : Element msg
    , openElement : Element msg
    , isOpen : Bool
    }


type alias Depth =
    Int


drillDownPanel : Theme -> PanelConfig msg -> Element msg
drillDownPanel theme config =
    let
        depthColor =
            let
                depthRgb =
                    1 - (0.1 * (toFloat <| config.depth + 1))
            in
            Element.fromRgb
                { red = depthRgb
                , green = depthRgb
                , blue = depthRgb
                , alpha = 1
                }
    in
    if config.isOpen then
        column [ theme |> borderRounded, Border.width 1, Border.color depthColor, padding <| (config.depth + 1) * 3, Border.innerGlow depthColor (toFloat config.depth + 3) ]
            [ row [ padding 1, pointer, customClick config.closeMsg, Font.size 11, Border.width 1, Border.color depthColor, theme |> borderRounded ] [ el [padding 1] (text theme.icons.opened), config.openHeader ]
            , el [ width fill ] config.openElement
            ]

    else
        row [ width fill, pointer, customClick config.openMsg ] [ config.closedElement ]

customClick : msg -> Attribute msg
customClick message =
    let
        clickWithStopPropagation = Html.Events.custom "click" (Decode.succeed { message = message, stopPropagation = True, preventDefault = True })
    in
    Element.htmlAttribute (clickWithStopPropagation)