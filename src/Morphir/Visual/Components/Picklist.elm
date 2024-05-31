module Morphir.Visual.Components.Picklist exposing
    ( State, init, view
    , getSelectedValue
    )

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
            -- this how you use the component in your view function
            [ Picklist.view
                -- this section is for wiring the component into your application,
                -- check out the Config type docs for further details
                { state = model.picklist
                , onStateChange = PicklistChanged
                , selectedvalue = model.selectedOption
                , onSelectionChange = OptionSelected
                }
                -- this is where you specify the selectable values
                -- each entry is a (DropdownElement msg value ) type record
                -- with .displayElement field for displaying the value to the user
                -- a .value field to store the actual used value
                -- and a .tag field for search purposes
            ]

@docs State, init, getSelectedvalue, view

-}

import Element
    exposing
        ( Element
        , alignRight
        , below
        , column
        , el
        , fill
        , focused
        , height
        , html
        , inFront
        , maximum
        , minimum
        , moveDown
        , none
        , paddingEach
        , padding
        , paddingXY
        , pointer
        , px
        , rgb255
        , rgba
        , row
        , shrink
        , spacing
        , text
        , width
        )
import Element.Background as Background
import Element.Border as Border
import Element.Events as Events
import Element.Font as Font
import Element.Input as Input
import FontAwesome as Icon
import FontAwesome.Attributes as Icon
import FontAwesome.Solid as Icon
import Morphir.Visual.Common exposing (colorToSvg)
import Morphir.Visual.Components.InputComponent exposing (searchInput)
import Morphir.Visual.Components.SelectableElement as SelectableElement
import Morphir.Visual.Theme as Theme exposing (Theme)
import Svg.Attributes


{-| Type that contains the internal state of this component.
-}
type alias State value =
    { selectedValue : Maybe value
    , dropDownOpen : Bool
    , searchText : Maybe String
    , targeted : Bool
    }


{-| Initialize the state of the component.
-}
init : Maybe value -> State value
init selectedValue =
    { selectedValue = selectedValue
    , dropDownOpen = False
    , searchText = Nothing
    , targeted = True
    }


{-| Get the currently selected value value.
-}
getSelectedValue : State value -> Maybe value
getSelectedValue state =
    state.selectedValue


type Msg value
    = ToggleDropdown
    | CloseDropdown
    | SearchText String


update : Msg value -> State value -> State value
update msg state =
    case msg of
        ToggleDropdown ->
            { state
                | dropDownOpen = not state.dropDownOpen
            }

        CloseDropdown ->
            if not state.targeted then
                { state
                    | dropDownOpen = False
                    , targeted = False
                }

            else
                state

        SearchText searchText ->
            case searchText of
                "" ->
                    { state
                        | searchText = Nothing
                    }

                _ ->
                    { state
                        | searchText = Just searchText
                        , dropDownOpen = True
                        , selectedValue = Nothing
                    }


{-| Configuration for the Picklist:

  - _state_
      - Internal state of the component.
  - _onStateChange_
      - Called when the internal state of the component changes.

-}
type alias Config msg value =
    { state : State value
    , onStateChange : State value -> msg
    }


{-| An element of the OrderedDropdown:

  - _tag_
      - Used for search purposes
  - _value_
      - The value of the selected element we'd like to use.
      - _displayElement_
          - How the elment should be displayed in the dropdown.

-}
type alias DropdownElement msg value =
    { tag : String
    , value : value
    , displayElement : Element msg
    }


{-| Invoke this from your view function to display the component. Arguments:

  - _theme_
      - Configuration that controls the styling of the component.
  - _config_
      - This is where you should do your wiring of states and event handlers. See the docs on `Config` for more details.
  - _selectableValues_
      - This is where you can specify what will be in the drop-down list. It's a tuple with 2 elements:
          - The "value" value that is returned by the selection change event.
          - The visual representation.

-}
view : Theme -> Config msg value -> List (DropdownElement msg value) -> List (DropdownElement msg value) -> Element msg
view theme config priorityElements generalElements =
    let
        state : State value
        state =
            config.state

        selectedValue : Maybe (Element msg)
        selectedValue =
            config.state
                |> getSelectedValue
                |> Maybe.andThen
                    (\selected ->
                        (priorityElements ++ generalElements)
                            |> List.filterMap
                                (\element ->
                                    if element.value == selected then
                                        Just <|
                                            element.displayElement

                                    else
                                        Nothing
                                )
                            |> List.head
                    )

        displaySelectedvalue : Element msg
        displaySelectedvalue =
            case selectedValue of
                Just selected ->
                    case config.state.searchText of
                        Just _ ->
                            Element.none

                        Nothing ->
                            row [ width fill, height fill, Background.color theme.colors.lightest, pointer, paddingXY 2 0, Theme.borderRounded theme ]
                                [ el [ width fill, height (shrink |> minimum (Theme.scaled 5 theme) |> maximum (Theme.scaled 5 theme)), Element.clipY ]
                                    selected
                                , el [ alignRight ]
                                    (html (Icon.caretDown |> Icon.styled [ Icon.lg ] |> Icon.view))
                                ]

                Nothing ->
                    Element.none

        displayDropDown : Element msg
        displayDropDown =
            if config.state.dropDownOpen then
                let
                    onSelectionChange : Maybe value -> msg
                    onSelectionChange selected =
                        config.onStateChange (init selected)
                in
                viewDropdown theme config.state.selectedValue onSelectionChange (priorityElements ++ generalElements) config.state.searchText
                    |> el
                        [ Events.onMouseEnter <| config.onStateChange { state | targeted = True }
                        , Events.onMouseLeave <| config.onStateChange { state | targeted = False }
                        ]

            else
                none

        inputElementAttributes : List (Element.Attribute msg)
        inputElementAttributes =
            [ width (shrink |> minimum (theme.fontSize * 14) |> maximum (theme.fontSize * 20))
            , paddingXY (theme |> Theme.mediumPadding) (theme |> Theme.smallPadding)
            , height fill
            , Border.width 1
            , theme |> Theme.borderRounded
            , Border.color (grey 201)
            , Font.size theme.fontSize
            , Background.color theme.colors.lightest
            , focused
                [ Border.color theme.colors.primaryHighlight
                , Border.shadow
                    { offset = ( 0, 0 )
                    , size = 0
                    , blur = 3
                    , color = theme.colors.primaryHighlight
                    }
                ]
            , below displayDropDown
            , inFront displaySelectedvalue
            , Events.onLoseFocus (config.onStateChange (update CloseDropdown config.state))
            ]
                ++ (if not config.state.dropDownOpen then
                        [ Events.onClick (config.onStateChange (update ToggleDropdown config.state)) ]

                    else
                        []
                   )
    in
    searchInput
        theme
        inputElementAttributes
        { onChange = \s -> config.onStateChange (update (SearchText s) config.state)
        , text = config.state.searchText |> Maybe.withDefault ""
        , label = Input.labelHidden "Search for an option"
        , placeholder = Just <| Input.placeholder [] viewUnselected
        }


viewDropdown : Theme -> Maybe value -> (Maybe value -> msg) -> List (DropdownElement msg value) -> Maybe String -> Element msg
viewDropdown theme selectedvalue onSelectionChange selectableValues searchText =
    let
        viewListItem : { icon : Element msg, label : Element msg, onClick : msg } -> Element msg
        viewListItem args =
            SelectableElement.view theme
                { onSelect = args.onClick
                , isSelected = False
                , content =
                    row
                        [ width fill
                        , paddingXY 0 (theme |> Theme.smallPadding)
                        , Font.color (grey 24)
                        ]
                        [ el [ width (px 20) ] args.icon
                        , args.label
                        ]
                }

        unselectElem : List (Element msg)
        unselectElem =
            if selectedvalue == Nothing then
                []

            else
                [ viewListItem
                    { icon =
                        html (Icon.xmark |> Icon.styled [ Icon.lg, Svg.Attributes.color (colorToSvg theme.colors.gray) ] |> Icon.view)
                    , label =
                        el [ Font.color (grey 160) ] (text "Clear selection")
                    , onClick = onSelectionChange Nothing
                    }
                ]

        selectableValueElems : List (Element msg)
        selectableValueElems =
            selectableValues
                |> (\list ->
                        case searchText of
                            Nothing ->
                                list

                            Just s ->
                                List.filter (\le -> String.contains (s |> String.toLower) (le.tag |> String.toLower)) list
                   )
                |> List.map
                    (\dropdownElement ->
                        viewListItem
                            { icon =
                                if selectedvalue == Just dropdownElement.value then
                                    html (Icon.check |> Icon.styled [ Icon.lg, Svg.Attributes.color (colorToSvg theme.colors.primaryHighlight) ] |> Icon.view)

                                else
                                    none
                            , label =
                                dropdownElement.displayElement
                            , onClick =
                                onSelectionChange (Just dropdownElement.value)
                            }
                    )
    in
    el
        [ width (shrink |> minimum (theme.fontSize * 14) |> maximum (theme.fontSize * 20))
        , moveDown 2
        , paddingEach
            { top = 4
            , right = 0
            , bottom = 4
            , left = 0
            }
        , Border.width 1
        , theme |> Theme.borderRounded
        , Border.color (grey 229)
        , Border.shadow
            { offset = ( 0, 2 )
            , size = 0
            , blur = 3
            , color = shadow 0.16
            }
        , Background.color theme.colors.lightest
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
