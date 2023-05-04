module Morphir.Visual.Components.DatePickerComponent exposing (..)

import DatePicker exposing (ChangeEvent(..))
import Element exposing (Element, mouseOver, paddingXY, text)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Morphir.SDK.LocalDate as LocalDate exposing (LocalDate)
import Morphir.Visual.Theme as Theme exposing (Theme)


type alias Config msg =
    { onStateChange : DatePickerState -> msg
    , label : Input.Label msg
    , placeholder : Maybe (Input.Placeholder msg)
    , state : DatePickerState
    }


type alias DatePickerState =
    { date : Result String (Maybe LocalDate)
    , pickerModel : DatePicker.Model
    , text : String
    }


initState : Maybe LocalDate -> Maybe LocalDate -> DatePickerState
initState maybeToday initialDate =
    let
        maybeSetToday : DatePicker.Model -> DatePicker.Model
        maybeSetToday =
            case maybeToday of
                Just today ->
                    DatePicker.setToday today

                Nothing ->
                    identity
    in
    case initialDate of
        Just date ->
            { pickerModel = DatePicker.initWithToday date |> maybeSetToday
            , date = Ok initialDate
            , text = LocalDate.toISOString date
            }

        Nothing ->
            { pickerModel = DatePicker.init |> maybeSetToday
            , date = Ok Nothing
            , text = ""
            }


view : Theme -> Config msg -> Element msg
view theme config =
    let
        default =
            DatePicker.defaultSettings
    in
    DatePicker.input
        [ Element.centerX
        , Element.centerY
        , Element.focused [ Border.color theme.colors.primaryHighlight ]
        , paddingXY (Theme.smallPadding theme) 3
        , Font.size theme.fontSize
        , Border.width 2
        ]
        { onChange = \changeEvent -> config.onStateChange (update changeEvent config.state)
        , selected = config.state.date |> Result.toMaybe |> Maybe.andThen identity
        , text = config.state.text
        , label = config.label
        , placeholder = config.placeholder
        , model = config.state.pickerModel
        , settings =
            { default
                | todayDayAttributes = [ Background.color theme.colors.brandSecondaryLight ]
                , selectedDayAttributes = [ Background.color theme.colors.brandPrimaryLight ]
                , dayAttributes = default.dayAttributes ++ [ mouseOver [ Background.color theme.colors.brandPrimary ] ]
                , monthYearAttribute = default.monthYearAttribute ++ [ mouseOver [ Background.color theme.colors.brandPrimary ]]
            }
        }


update : DatePicker.ChangeEvent -> DatePickerState -> DatePickerState
update changeEvent model =
    let
        handleTextChange : String -> Result String (Maybe LocalDate)
        handleTextChange text =
            if text == "" then
                Ok Nothing

            else
                case LocalDate.fromISO text of
                    Just d ->
                        Ok <| Just d

                    Nothing ->
                        Err "Invalid date format"
    in
    case changeEvent of
        DateChanged date ->
            -- update both date and text
            { model
                | date = Ok <| Just date
                , text = date |> LocalDate.toISOString
                , pickerModel = model.pickerModel |> DatePicker.close
            }

        TextChanged text ->
            { model
                | date = handleTextChange text
                , text = text
            }

        PickerChanged subMsg ->
            -- internal stuff changed
            -- call DatePicker.update
            { model
                | pickerModel =
                    model.pickerModel
                        |> DatePicker.update subMsg
            }
