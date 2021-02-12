module Morphir.Visual.Components.Theme exposing (..)

import Element


type alias Theme =
    { fontSize : Int
    , smallSpacing : Int
    , mediumSpacing : Int
    , largeSpacing : Int
    , smallPadding : Int
    , mediumPadding : Int
    , largePadding : Int
    }


type alias Style =
    { fontSize : Int
    }


scaled : Int -> Style -> Int
scaled scaleValue style =
    Element.modular (toFloat style.fontSize) 1.25 scaleValue |> round
