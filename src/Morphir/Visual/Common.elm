module Morphir.Visual.Common exposing (cssClass, definition, element, grayScale, nameToText)

import Element exposing (Attribute, Color, Element, column, el, height, paddingEach, rgb, row, shrink, spacing, text, width)
import Element.Font as Font
import Html exposing (Html)
import Html.Attributes exposing (class)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.Theme exposing (mediumPadding, mediumSpacing)


cssClass : String -> Attribute msg
cssClass className =
    Element.htmlAttribute (class className)


nameToText : Name -> String
nameToText name =
    name
        |> Name.toHumanWords
        |> String.join " "


element : Element msg -> Html msg
element elem =
    Element.layoutWith
        { options =
            [ Element.noStaticStyleSheet
            ]
        }
        [ width shrink
        , height shrink
        ]
        elem


grayScale : Float -> Color
grayScale v =
    rgb v v v


definition : Config msg -> String -> Element msg -> Element msg
definition config header body =
    column [ mediumSpacing config.state.theme |> spacing ]
        [ row [ mediumSpacing config.state.theme |> spacing ]
            [ el [ Font.bold ] (text header)
            , el [] (text "=")
            ]
        , el [ paddingEach { left = mediumPadding config.state.theme, right = mediumPadding config.state.theme, top = 0, bottom = 0 } ]
            body
        ]
