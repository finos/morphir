module Morphir.Visual.Components.Picklist exposing (State, init, view)

{-| This module implements a component that allows users to pick an item from a dropdown list.


# Usage

    type alias Model =
        { picklist : Picklist.State -- the internal state of this component
        , selectedOption : Maybe Option -- the value that this component is used to set

        -- ... other fields ...
        }

    -- we can use any type except for functions to represent the values to choose from
    type Option
        = Option1
        | Option2

    type Msg
        = PicklistChanged Picklist.State -- message used to update the component's internal state
        | OptionSelected (Maybe Option) -- message sent when the selection changes
        | OtherMessage

    -- ... other messages ...
    update : Msg -> Model -> Model
    update msg model =
        case msg of
            PicklistChanged newState ->
                -- when the internal state changes we simply update it in the model
                { model
                    | picklist = newState
                }

            OptionSelected maybeOption ->
                -- when the selection changes we decide what to do, here we simply update the selection
                { model
                    | selectedOption = maybeOption
                }

    view : Model -> Element msg
    view model =
        column []
            [ Picklist.view
                { state = model.picklist
                , onStateChange = PicklistChanged
                , selectedTag = model.selectedOption
                , onSelectionChange = OptionSelected
                }
                [ ( Option1, "Option A" )
                , ( Option2, "Option B" )
                ]
            ]

@docs State, init, view

-}

import Element exposing (Element, alignRight, below, column, el, fill, focused, height, html, mouseOver, moveDown, none, paddingEach, px, rgb255, rgba, row, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Events as Events
import Element.Font as Font
import Element.Input as Input
import FontAwesome as Icon
import FontAwesome.Attributes as Icon
import FontAwesome.Solid as Icon
import Svg.Attributes


{-| Opaque type that contains the internal state of this component.
-}
type State
    = State InternalState


type alias InternalState =
    { dropDownOpen : Bool
    }


type Msg tag
    = ToggleDropdown
    | CloseDropdown


init : State
init =
    State
        { dropDownOpen = False
        }


update : Msg tag -> InternalState -> InternalState
update msg state =
    case msg of
        ToggleDropdown ->
            { state
                | dropDownOpen = not state.dropDownOpen
            }

        CloseDropdown ->
            { state
                | dropDownOpen = False
            }


{-| Configuration for the Picklist:

  - _state_
      - Internal state of the component.
  - _onStateChange_
      - Called when the internal state of the component changes.
  - _selectedTag_
      - Sets the selection using the tag value.
      - It is an optional value. If it's not set that means nothing is selected.
  - _onSelectionChange_
      - Called when the selection changes.

-}
type alias Config msg tag =
    { state : State
    , onStateChange : State -> msg
    , selectedTag : Maybe tag
    , onSelectionChange : Maybe tag -> msg
    }


{-| -}
view : Config msg tag -> List ( tag, Element msg ) -> Element msg
view config selectableValues =
    let
        selectedValue : Maybe (Element msg)
        selectedValue =
            config.selectedTag
                |> Maybe.andThen
                    (\selected ->
                        selectableValues
                            |> List.filterMap
                                (\( tag, content ) ->
                                    if tag == selected then
                                        Just content

                                    else
                                        Nothing
                                )
                            |> List.head
                    )

        internalState : InternalState
        internalState =
            case config.state of
                State s ->
                    s
    in
    Input.button
        [ width (px 240)
        , height (px 30)
        , paddingEach
            { top = 0
            , right = 12
            , bottom = 0
            , left = 12
            }
        , Border.width 1
        , Border.rounded 4
        , Border.color (grey 201)
        , focused
            [ Border.color (rgb255 27 150 255)
            , Border.shadow
                { offset = ( 0, 0 )
                , size = 0
                , blur = 3
                , color = rgb255 1 118 211
                }
            ]
        , below
            (if internalState.dropDownOpen then
                viewDropdown config.selectedTag config.onSelectionChange selectableValues

             else
                none
            )
        , Events.onLoseFocus (config.onStateChange (State (update CloseDropdown internalState)))
        ]
        { onPress = Just (config.onStateChange (State (update ToggleDropdown internalState)))
        , label =
            let
                labelContent : Element msg
                labelContent =
                    case selectedValue of
                        Just selected ->
                            selected

                        Nothing ->
                            el
                                [ Font.color (grey 160)
                                ]
                                viewUnselected
            in
            row [ width fill, height fill ]
                [ labelContent
                , el [ alignRight ]
                    (html (Icon.caretDown |> Icon.styled [ Icon.lg ] |> Icon.view))
                ]
        }


viewDropdown : Maybe tag -> (Maybe tag -> msg) -> List ( tag, Element msg ) -> Element msg
viewDropdown selectedTag onSelectionChange selectableValues =
    let
        viewListItem : { icon : Element msg, label : Element msg, onClick : msg } -> Element msg
        viewListItem args =
            row
                [ height (px 32)
                , width fill
                , paddingEach
                    { top = 8
                    , right = 12
                    , bottom = 8
                    , left = 12
                    }
                , spacing 8
                , Font.color (grey 24)
                , mouseOver
                    [ Background.color (grey 243)
                    ]
                , Events.onClick args.onClick
                ]
                [ el [ width (px 20) ] args.icon
                , args.label
                ]

        unselectElem : List (Element msg)
        unselectElem =
            if selectedTag == Nothing then
                []

            else
                [ viewListItem
                    { icon =
                        html (Icon.xmark |> Icon.styled [ Icon.lg, Svg.Attributes.color "rgb(201, 201, 201)" ] |> Icon.view)
                    , label =
                        el [ Font.color (grey 160) ] (text "Clear selection")
                    , onClick = onSelectionChange Nothing
                    }
                ]

        selectableValueElems : List (Element msg)
        selectableValueElems =
            selectableValues
                |> List.map
                    (\( tag, content ) ->
                        viewListItem
                            { icon =
                                if selectedTag == Just tag then
                                    html (Icon.check |> Icon.styled [ Icon.lg, Svg.Attributes.color "rgb(1, 118, 211)" ] |> Icon.view)

                                else
                                    none
                            , label =
                                content
                            , onClick =
                                onSelectionChange (Just tag)
                            }
                    )
    in
    el
        [ moveDown 2
        , paddingEach
            { top = 4
            , right = 0
            , bottom = 4
            , left = 0
            }
        , width fill
        , Border.width 1
        , Border.rounded 4
        , Border.color (grey 229)
        , Border.shadow
            { offset = ( 0, 2 )
            , size = 0
            , blur = 3
            , color = shadow 0.16
            }
        ]
        (column
            [ width fill
            , height fill
            ]
            (unselectElem ++ selectableValueElems)
        )


viewUnselected : Element msg
viewUnselected =
    text "Select an Option…"


grey c =
    rgb255 c c c


shadow c =
    rgba 0 0 0 c
