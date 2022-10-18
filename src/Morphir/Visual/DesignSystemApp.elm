module Morphir.Visual.DesignSystemApp exposing (..)

import Array exposing (Array)
import Browser
import Element exposing (Element, column, el, htmlAttribute, layout, padding, spacing, text)
import Element.Font as Font
import FontAwesome.Styles as Icon
import Html exposing (Html)
import Morphir.Visual.Components.Picklist as Picklist


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
    { picklist : Picklist.State
    , picklistSelection : Maybe Int
    }


type Msg
    = DoNothing
    | PicklistChanged Picklist.State
    | PicklistSelectionChanged (Maybe Int)


init : Model
init =
    let
        components : Components
        components =
            { picklist = Picklist.init
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
        (column [ spacing 20 ]
            [ el [] (text (Debug.toString c.picklist))
            , el [] (text (Debug.toString c.picklistSelection))
            , Picklist.view
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
            ]
        )
