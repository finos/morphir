module Morphir.Visual.Components.SectionComponent exposing (..)

import Element exposing (Element, column, el, fill, height, none, pointer, row, spacing, text, width)
import Element.Background as Background
import Element.Events exposing (onClick)
import Element.Font as Font
import Element.Input
import Morphir.Visual.Theme exposing (Theme, mediumSpacing, smallSpacing)


type alias Config msg =
    { title : String
    , content : () -> Element msg
    , onToggle : msg
    , isOpen : Bool
    }


view : Theme -> Config msg -> Element msg
view theme config =
    let
        header : Element msg
        header =
            let
                icon : String
                icon =
                    if config.isOpen then
                        theme.icons.opened

                    else
                        theme.icons.closed
            in
            Element.Input.button
                []
                { onPress = Just config.onToggle
                , label =
                    row
                        [ width fill
                        , Background.color theme.colors.lightest
                        , Font.bold
                        , smallSpacing theme |> spacing
                        , pointer
                        ]
                        [ el [] (text icon), el [ Font.size theme.fontSize ] (text config.title) ]
                }
    in
    column [ width fill, height fill, Background.color theme.colors.lightest, mediumSpacing theme |> spacing ]
        [ header
        , if config.isOpen then
            config.content ()

          else
            none
        ]
