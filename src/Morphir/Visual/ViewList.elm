module Morphir.Visual.ViewList exposing (..)

import Html exposing (Html)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value exposing (Value)


view : Type ta -> List (Value ta va) -> Html msg
view itemType items =
    Html.div [] [ Html.text "TODO" ]
