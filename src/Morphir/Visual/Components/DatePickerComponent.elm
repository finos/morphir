module Morphir.Visual.Components.DatePickerComponent exposing (..)

import Element exposing (Element, mouseOver, paddingXY, text)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html
import Html.Attributes exposing (for, style, type_, value)
import Html.Events exposing (onInput)
import Morphir.SDK.LocalDate as LocalDate exposing (LocalDate)
import Morphir.Visual.Theme as Theme exposing (Theme)


type alias Config msg =
    { onStateChange : DatePickerState -> msg
    , label : Element msg
    , placeholder : Maybe (Input.Placeholder msg)
    , state : DatePickerState
    }


type alias DatePickerState =
    { date : Maybe LocalDate
    }


initState : Maybe LocalDate -> DatePickerState
initState initialDate =
    { date = initialDate }


view : Theme -> Config msg -> Element msg
view theme config =
    let
        state =
            config.state
    in
    Html.label [style "display" "flex"]
        [ Html.div
            [ style "background-color" "rgb(51, 76, 102 )"
            , style "padding" "5px"
            , style "margin-right" "5px"
            , style "display" "inline"
            , style "color" "rgb(179, 179, 179)"
            ]
            [ Html.text "local date" ]
        , Html.input
            [ type_ "date"
            , value (config.state.date |> Maybe.map LocalDate.toISOString |> Maybe.withDefault "")
            , onInput (\datestr -> config.onStateChange { state | date = LocalDate.fromISO datestr })
            , for "local date"
            ]
            []
        ]
        |> Element.html
