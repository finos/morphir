module Morphir.Visual.Components.TabsComponent exposing (TabsComponentConfig, Tab, view)

{-| This module implements a component that allows users to pick between content displayed in tabs.


# Usage


    type alias Model =
        { activeTab : Int -- the index of the selected tab

        -- ... other fields ...
        }

    type Msg
        = SwitchTab Int -- message used to change the active tab

    -- ... other messages ...
    update : Msg -> Model -> Model
    update msg model =
        case msg of
            SwitchTab index ->
                -- when the
                { model
                    | activeTab = index
                }

    -- ... other message handler ... --

@docs TabsComponentConfig, Tab, view

-}

import Array exposing (Array)
import Element exposing (Element, column, el, fill, height, mouseOver, none, padding, pointer, row, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Events exposing (onClick)
import Element.Font as Font
import Element.Input
import Morphir.Visual.Theme as Theme exposing (Theme)


{-| A type defining a tab:

  - _name_
      - The name of the tab displayed on the tab header.
      - _content_
          - The content displayed when the tab is active.

-}
type alias Tab msg =
    { name : String
    , content : () -> Element msg
    }


{-| Configuration for the tabs component:

  - _theme_
      - Theme configuration.
      - _tabs_
          - List of tabs content elements.
  - _onSwitchTab_
      - Called when a tab header is clicked.
  - _activeTab_
      - The index of the actibe tab.

-}
type alias TabsComponentConfig msg =
    { tabs : Array (Tab msg)
    , onSwitchTab : Int -> msg
    , activeTab : Int
    }



{-
   Display a Tabs Component
-}


view : Theme -> TabsComponentConfig msg -> Element msg
view theme config =
    let
        tabHeader : String -> Int -> Element msg
        tabHeader name index =
            let
                isActive : Bool
                isActive =
                    config.activeTab == index

                activeStyles : List (Element.Attribute msg)
                activeStyles =
                    if isActive then
                        [ Font.bold, Border.color theme.colors.primaryHighlight ]

                    else
                        []

                focusedStyles : List (Element.Attr Never Never)
                focusedStyles = 
                    if not isActive then
                        [ Background.color theme.colors.gray, Border.color theme.colors.primaryHighlight ]
                    else
                        [ Background.color theme.colors.lightest, Border.color theme.colors.primaryHighlight ]
            in
            Element.Input.button
                ([ pointer
                 , Background.color theme.colors.lightest
                 , Font.size theme.fontSize
                 , Border.widthEach { top = 0, left = 0, right = 0, bottom = 2 }
                 , mouseOver [ Background.color theme.colors.gray, Border.color theme.colors.primaryHighlight ]
                 , padding (Theme.mediumPadding theme)
                 , Border.color theme.colors.lightest
                 , Element.focused focusedStyles
                 ]
                    ++ activeStyles
                )
                { onPress = Just <| config.onSwitchTab index, label = text name }

        tabHeaders : List (Element msg)
        tabHeaders =
            Array.toList <| Array.indexedMap (\i tab -> tabHeader tab.name i) config.tabs

        activeTab : Element msg
        activeTab =
            case Array.get config.activeTab config.tabs of
                Just tab ->
                    tab.content ()

                Nothing ->
                    none
    in
    column [ width fill, height fill, spacing (Theme.largeSpacing theme) ]
        [ row [ width fill, spacing (Theme.smallSpacing theme), Theme.borderBottom 1, Border.color theme.colors.gray ] tabHeaders, el [ width fill, height fill ] activeTab ]
