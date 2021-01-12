module Morphir.Visual.Common exposing (cssClass, element, nameToText)

import Element exposing (Attribute, Element, height, shrink, width)
import Html exposing (Html)
import Html.Attributes exposing (class)
import Morphir.IR.Name as Name exposing (Name)


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
