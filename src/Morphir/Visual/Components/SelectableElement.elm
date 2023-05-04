module Morphir.Visual.Components.SelectableElement exposing (..)

import Element exposing (Element, el, fill, htmlAttribute, mouseOver, pointer, width)
import Element.Background as Background
import Element.Border as Border
import Element.Events exposing (onClick)
import Element.Font as Font
import Element.Input
import Html.Attributes exposing (tabindex)
import Morphir.Visual.Theme exposing (Theme)
import Bootstrap.ListGroup exposing (active)


type alias Config msg =
    { content : Element msg
    , onSelect : msg
    , isSelected : Bool
    }


view : Theme -> Config msg -> Element msg
view theme config =
    let
        styles : List (Element.Attribute msg)
        styles =
            [ width fill
            , pointer
            , Border.widthEach { left = 2, right = 0, bottom = 0, top = 0 }
            , Border.color theme.colors.lightest
            , mouseOver focusedStyles
            , Element.focused focusedStyles
            ]
        focusedStyles : List (Element.Attr Never Never)
        focusedStyles = 
            if not config.isSelected then
                [ Background.color theme.colors.gray]
            else
                [ Background.color theme.colors.brandPrimaryLight]

        activeStyles : List (Element.Attribute msg)
        activeStyles =
            if config.isSelected then
                [ Font.bold
                , Background.color theme.colors.brandPrimaryLight
                , Border.color theme.colors.primaryHighlight
                ]

            else
                []
    in
    Element.Input.button (styles ++ activeStyles) { onPress = Just config.onSelect, label = config.content }
