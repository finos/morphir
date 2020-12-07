module Morphir.Visual.Common exposing (cssClass, nameToText)

import Element exposing (Attribute)
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
