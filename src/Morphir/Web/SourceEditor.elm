module Morphir.Web.SourceEditor exposing (..)

import Element exposing (Element, fill, height, scrollbars, text, width)
import Element.Font as Font
import Element.Input as Input


view : String -> (String -> msg) -> Element msg
view sourceCode onChange =
    Input.multiline
        [ width fill
        , height fill

        --, scrollbars
        ]
        { text = sourceCode
        , placeholder = Just (Input.placeholder [] (text "Type your model here"))
        , onChange = onChange
        , label = Input.labelHidden "Model Source"
        , spellcheck = False
        }
