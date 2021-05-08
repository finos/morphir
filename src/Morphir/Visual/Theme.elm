module Morphir.Visual.Theme exposing (..)

import Element


type alias Theme =
    { fontSize : Int
    , decimalDigit : Int
    }


type alias ThemeConfig =
    { fontSize : Maybe Int
    , decimalDigit : Maybe Int
    }


fromConfig : Maybe ThemeConfig -> Theme
fromConfig maybeConfig =
    case maybeConfig of
        Just config ->
            { fontSize = config.fontSize |> Maybe.withDefault 12, decimalDigit = config.decimalDigit |> Maybe.withDefault 2 }

        Nothing ->
            { fontSize = 12, decimalDigit = 2 }


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


scaled : Int -> Theme -> Int
scaled scaleValue theme =
    Element.modular (toFloat theme.fontSize) 1.25 scaleValue |> round
