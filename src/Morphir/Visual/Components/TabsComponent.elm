module Morphir.Visual.Components.TabsComponent exposing (..)

import Array exposing (Array)
import Element exposing (Element, column, el, fill, height, mouseOver, none, padding, pointer, row, spacing, text, width)
import Element.Border as Border
import Element.Events exposing (onClick)
import Element.Font as Font
import Morphir.Visual.Theme as Theme exposing (Theme)


type alias TabsComponentConfig msg =
    { theme : Theme
    , tabs : Array (Tab msg)
    , onSwitchTab : Int -> msg
    , activeTab : Int
    }


type alias Tab msg =
    { name : String
    , content : Element msg
    }


tabsComponent : TabsComponentConfig msg -> Element msg
tabsComponent config =
    let
        tabHeader : String -> Int -> Element msg
        tabHeader name index =
            let
                isActive : Bool
                isActive =
                    config.activeTab == index

                activeStyles =
                    if isActive then
                        [ Font.bold, Border.color config.theme.colors.primaryHighlight ]

                    else
                        []
            in
            el
                ([ onClick (config.onSwitchTab index)
                 , pointer
                 , Border.widthEach { top = 0, left = 0, right = 0, bottom = 2 }
                 , mouseOver [ Border.color config.theme.colors.primaryHighlight ]
                 , padding (Theme.mediumPadding config.theme)
                 , Border.color config.theme.colors.lightest
                 ]
                    ++ activeStyles
                )
                (text name)

        tabHeaders : List (Element msg)
        tabHeaders =
            Array.toList <| Array.indexedMap (\i tab -> tabHeader tab.name i) config.tabs

        activeTab : Element msg
        activeTab =
            case Array.get config.activeTab config.tabs of
                Just tab ->
                    tab.content

                Nothing ->
                    none
    in
    column [ width fill, height fill, spacing (Theme.largeSpacing config.theme) ]
        [ row [ width fill, spacing (Theme.smallSpacing config.theme), Theme.borderBottom 1, Border.color config.theme.colors.gray ] tabHeaders, el [ width fill ] activeTab ]
