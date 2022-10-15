module Morphir.Visual.Theme exposing (..)

import Element exposing (Color, Element, Attribute, el, fill, paddingXY, rgb, rgba, rgb255, row, spacing, toRgb, width, height, table, none, mouseOver)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font exposing (center)
import Element.Input as Input
import Html exposing (div, text)
import Html.Attributes exposing (style)
import Element exposing (Attr)


type alias Theme =
    { fontSize : Int
    , decimalDigit : Int
    , colors : Colors
    }


type alias Colors =
    { lightest : Color
    , darkest : Color
    , primaryHighlight : Color
    , secondaryHighlight : Color
    , positive : Color
    , positiveLight : Color
    , negative : Color
    , negativeLight : Color
    , backgroundColor : Color
    , selectionColor : Color
    , secondaryInformation : Color
    , gray : Color
    }


type alias ThemeConfig =
    { fontSize : Maybe Int
    , decimalDigit : Maybe Int
    }


defaultColors : Colors
defaultColors =
    { lightest = rgb 1 1 1
    , darkest = rgb 0.1 0.1 0.1
    , primaryHighlight = rgb255 0 163 225
    , secondaryHighlight = rgb255 255 105 0
    , positive = rgb 0 0.6 0
    , positiveLight = rgba 0 0.6 0 0.5
    , negative = rgb 0.7 0 0
    , negativeLight = rgba 0.7 0 0 0.5
    , backgroundColor = rgb 0.9529 0.9176 0.8078
    , selectionColor = rgb 0.8 0.9 0.9
    , secondaryInformation = rgb 0.5 0.5 0.5
    , gray = rgb 0.9 0.9 0.9
    }

labelStyles : Theme -> List (Attribute msg)
labelStyles theme =
            [ width fill
            , height fill
            , paddingXY 10 5
            , Border.widthEach { bottom = 1, top = 0, left = 0, right = 0 }
            , Border.color theme.colors.backgroundColor
            ]

boldLabelStyles : Theme -> List (Attribute msg)
boldLabelStyles theme =  Font.bold :: labelStyles theme

fromConfig : Maybe ThemeConfig -> Theme
fromConfig maybeConfig =
    case maybeConfig of
        Just config ->
            { fontSize = config.fontSize |> Maybe.withDefault 10
            , decimalDigit = config.decimalDigit |> Maybe.withDefault 2
            , colors = defaultColors
            }

        Nothing ->
            { fontSize = 10
            , decimalDigit = 2
            , colors = defaultColors
            }


smallSpacing : Theme -> Int
smallSpacing theme =
    scaled -3 theme


mediumSpacing : Theme -> Int
mediumSpacing theme =
    scaled 0 theme


largeSpacing : Theme -> Int
largeSpacing theme =
    scaled 4 theme


smallPadding : Theme -> Int
smallPadding theme =
    scaled -3 theme


mediumPadding : Theme -> Int
mediumPadding theme =
    scaled 0 theme


largePadding : Theme -> Int
largePadding theme =
    scaled 4 theme

borderRounded : Attribute msg
borderRounded = 
    Border.rounded 3

borderBottom : Int -> Attribute msg
borderBottom width = 
    Border.widthEach { top = 0, left = 0, right = 0, bottom = width }

scaled : Int -> Theme -> Int
scaled scaleValue theme =
    Element.modular (toFloat theme.fontSize) 1.25 scaleValue |> round


fontColorFor : Color -> Theme -> Color
fontColorFor backgroundColor theme =
    let
        backgroundBrightness =
            let
                rgb =
                    toRgb backgroundColor
            in
            (rgb.red + rgb.green * rgb.blue) / 3
    in
    if backgroundBrightness < 0.5 then
        theme.colors.lightest

    else
        theme.colors.darkest


button : msg -> String -> Color -> Theme -> Element msg
button msg label color theme =
    Input.button
        [ Font.bold
        , Border.solid
        , Border.rounded 3
        , paddingXY
            (theme |> scaled 1)
            (theme |> scaled -3)
        , Background.color color
        , Font.color (theme |> fontColorFor color)
        ]
        { onPress = Just msg
        , label = Element.text label
        }


header : Theme -> { left : List (Element msg), middle : List (Element msg), right : List (Element msg) } -> Element msg
header theme parts =
    row
        [ width fill
        ]
        [ row [ spacing (theme |> scaled 1) ] parts.left
        , row
            [ width fill
            , center
            ]
            parts.middle
        , row
            [ spacing (theme |> scaled 1)
            ]
            parts.right
        ]

twoColumnTableView : List record -> (record -> Element msg) -> (record -> Element msg) -> Element msg
twoColumnTableView tableData leftView rightView = 
    table
        [ width fill
        ]
        { columns =
            [ { header = none
              , width = fill
              , view = leftView
              }
            , { header = none
              , width = fill
              , view = rightView
              }
            ]
        , data = tableData
        }


ellipseText : String -> Element msg
ellipseText str =
    Element.html <|
        div
            [ style "text-overflow" "ellipsis"
            , style "overflow" "hidden"
            , style "width" "100%"
            , style "flex-basis" "auto"
            ]
            [ text str ]