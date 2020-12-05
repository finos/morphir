module Morphir.Visual.Common exposing (..)

import Element exposing (Attribute)
import Html.Attributes exposing (class)


cssClass : String -> Attribute msg
cssClass className =
    Element.htmlAttribute (class className)
