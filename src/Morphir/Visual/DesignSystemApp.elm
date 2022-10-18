module Morphir.Visual.DesignSystemApp exposing (..)

import Array exposing (Array)
import Browser
import Element exposing (Element, column, el, htmlAttribute, layout, none, padding, paddingEach, rgb, row, spacing, text)
import Element.Background as Background
import Element.Font as Font
import FontAwesome.Styles as Icon
import Html exposing (Html)
import Morphir.Visual.Components.DrillDownPanel as DrillDownPanel
import Morphir.Visual.Components.Picklist as Picklist
import Morphir.Visual.Components.TabsComponent as TabsComponent
import Morphir.Visual.Theme as Theme exposing (Theme)


main : Program () Model Msg
main =
    Browser.sandbox
        { init = init
        , view = view
        , update = update
        }


type alias Model =
    Components


type alias Components =
    { theme : Theme
    , activeTab : Int
    , drillDownIsOpen : Bool
    , picklist : Picklist.State
    , picklistSelection : Maybe Int
    }


type Msg
    = DoNothing
    | SwitchTab Int
    | OpenDrillDown
    | CloseDrillDown
    | PicklistChanged Picklist.State
    | PicklistSelectionChanged (Maybe Int)


init : Model
init =
    let
        components : Components
        components =
            { theme = Theme.fromConfig Nothing
            , activeTab = 0
            , drillDownIsOpen = False
            , picklist = Picklist.init
            , picklistSelection = Nothing
            }
    in
    components


update : Msg -> Model -> Model
update msg model =
    case msg of
        DoNothing ->
            model

        PicklistChanged newState ->
            { model
                | picklist = newState
            }

        PicklistSelectionChanged maybeSelectedTag ->
            { model
                | picklistSelection = maybeSelectedTag
            }

        SwitchTab newActiveTab ->
            { model
                | activeTab = newActiveTab
            }

        OpenDrillDown ->
            { model
                | drillDownIsOpen = True
            }

        CloseDrillDown ->
            { model
                | drillDownIsOpen = False
            }


view : Model -> Html Msg
view model =
    Html.div []
        [ Icon.css
        , layout [ Font.size 12 ]
            (viewComponents model)
        ]


viewComponents : Components -> Element Msg
viewComponents c =
    el [ padding 20 ]
        (column [ spacing 40 ]
            [ viewComponent "Tabs"
                none
                (text (Debug.toString c.activeTab))
                (TabsComponent.tabsComponent
                    { theme = c.theme
                    , tabs =
                        Array.fromList
                            [ { name = "Tab 1"
                              , content = text "Content 1"
                              }
                            , { name = "Tab 2"
                              , content = text "Content 2"
                              }
                            ]
                    , onSwitchTab = SwitchTab
                    , activeTab = c.activeTab
                    }
                )
            , viewComponent "Drill-down Panel"
                none
                (text (Debug.toString c.drillDownIsOpen))
                (DrillDownPanel.drillDownPanel
                    { openMsg = OpenDrillDown
                    , closeMsg = CloseDrillDown
                    , depth = 1
                    , closedElement = text "Closed"
                    , openHeader = text "Header"
                    , openElement = text "Content"
                    , isOpen = c.drillDownIsOpen
                    }
                )
            , viewComponent "Picklist"
                (text (Debug.toString c.picklist))
                (text (Debug.toString c.picklistSelection))
                (Picklist.view
                    { state = c.picklist
                    , onStateChange = PicklistChanged
                    , selectedTag = c.picklistSelection
                    , onSelectionChange = PicklistSelectionChanged
                    }
                    [ ( 1, text "Option A" )
                    , ( 2, text "Option B" )
                    , ( 3, text "Option C" )
                    , ( 4, text "Option D" )
                    , ( 5, text "Option E" )
                    , ( 6, text "Option F" )
                    , ( 7, text "Option G" )
                    ]
                )
            ]
        )


viewComponent : String -> Element msg -> Element msg -> Element msg -> Element msg
viewComponent title internalState externalState component =
    column [ spacing 20 ]
        [ el [ Font.size 24 ] (text title)
        , column [ paddingEach { top = 0, right = 0, bottom = 0, left = 20 }, spacing 20 ]
            [ row [ spacing 10 ] [ text "Internal State:", internalState ]
            , row [ spacing 10 ] [ text "External State:", externalState ]
            , el
                [ padding 20
                , Background.color (rgb 0.9 0.9 0.9)
                ]
                component
            ]
        ]
