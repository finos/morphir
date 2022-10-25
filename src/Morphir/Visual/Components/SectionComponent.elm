module Morphir.Visual.Components.SectionComponent exposing (..)

import Element exposing (Element, column, el, fill, height, none, pointer, row, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Events exposing (onClick)
import Element.Font as Font
import Morphir.Visual.Theme exposing (Theme, scaled, smallSpacing, mediumSpacing)


type alias Config msg =
    { title : String
    , content : Element msg
    , onToggle : msg
    , isOpen : Bool
    }


view : Theme -> Config msg -> Element msg
view theme config =
    let
        header =
            let
                icon =
                    if config.isOpen then
                        theme.icons.opened

                    else
                        theme.icons.closed
            in
            row
                [ width fill
                , Background.color theme.colors.lightest
                , Font.bold
                , smallSpacing theme |> spacing
                , onClick config.onToggle
                , pointer
                ]
                [ el [] (text icon), el [ Font.size (theme |> scaled 2) ] (text config.title) ]
    in
    column [ width fill, height fill, Background.color theme.colors.lightest, mediumSpacing theme |> spacing]
        [ header
        , if config.isOpen then
            config.content

          else
            none
        ]
