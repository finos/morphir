module Morphir.Visual.Components.DrillDownPanel exposing (..)

import Element exposing (Attribute, Color, Element, column, el, fill, html, htmlAttribute, padding, paddingEach, pointer, px, rgba, row, width)
import Element.Background as Background
import Element.Border as Border
import FontAwesome as Icon
import FontAwesome.Solid as Solid
import Html.Attributes exposing (style)
import Html.Events
import Json.Decode as Decode
import Morphir.Visual.Common exposing (colorToSvg)
import Morphir.Visual.Theme as Theme exposing (Theme)
import Svg.Attributes


type alias PanelConfig msg =
    { openMsg : msg
    , closeMsg : msg
    , depth : Depth
    , closedElement : Element msg
    , openHeader : Element msg
    , openElement : Element msg
    , isOpen : Bool
    , zIndex : Int
    }


type alias Depth =
    Int


drillDownPanel : Theme -> PanelConfig msg -> Element msg
drillDownPanel theme config =
    if config.isOpen then
        column
            []
            [ row
                [ width fill
                , pointer
                , paddingEach { top = 0, right = theme |> Theme.smallPadding, bottom = 0, left = 0 }
                , customClick config.closeMsg
                , Border.roundEach { topRight = 4, bottomRight = 0, bottomLeft = 0, topLeft = 4 }
                , Border.widthEach { bottom = 0, top = 2, right = 2, left = 2 }
                , Border.color (rgba 0 0 0 0.1)
                ]
                [ el [ width (theme |> Theme.largeSpacing |> px) ] (collapseIcon theme)
                , config.openHeader
                ]
            , el
                [ width fill
                , Border.roundEach { topRight = 0, bottomRight = 4, bottomLeft = 4, topLeft = 0 }
                , Border.width 1
                , Border.color (rgba 0 0 0 0.05)
                , theme |> Theme.smallPadding |> padding
                , Border.innerShadow
                    { offset = ( 0, 2 )
                    , size = 0
                    , blur = 4
                    , color = rgba 0 0 0 0.2
                    }
                , Background.color theme.colors.lightest
                , htmlAttribute (style "filter" "brightness(97%)")
                , htmlAttribute (style "z-index" (String.fromInt config.zIndex))
                ]
                config.openElement
            ]

    else
        row
            [ width fill
            , pointer
            , paddingEach { top = 0, right = theme |> Theme.smallPadding, bottom = 0, left = 0 }
            , customClick config.openMsg
            , Border.rounded 4
            , Border.width 2
            , Border.color (rgba 0 0 0 0.1)
            , Background.color theme.colors.lightest
            ]
            [ el [ width (theme |> Theme.largeSpacing |> px) ] (expandIcon theme)
            , config.closedElement
            ]


expandIcon : Theme -> Element msg
expandIcon theme =
    Solid.caretRight |> Icon.styled [ Svg.Attributes.color (colorToSvg theme.colors.mediumGray) ] |> Icon.view |> html


collapseIcon : Theme -> Element msg
collapseIcon theme =
    Solid.caretDown |> Icon.styled [ Svg.Attributes.color (colorToSvg theme.colors.mediumGray) ] |> Icon.view |> html


customClick : msg -> Attribute msg
customClick message =
    let
        clickWithStopPropagation =
            Html.Events.custom "click" (Decode.succeed { message = message, stopPropagation = True, preventDefault = True })
    in
    Element.htmlAttribute clickWithStopPropagation
