module Morphir.Web.Theme exposing (..)

import Element exposing (Element)


type alias Theme msg =
    { button :
        { onPress : msg, label : String } -> Element msg
    , disabledButton : String -> Element msg
    , heading : Int -> String -> Element msg
    }
