module Morphir.Visual.ViewValue exposing (..)

import Html exposing (Html)
import Html.Attributes exposing (class, title)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Visual.ViewList as ViewList
import Morphir.Visual.ViewLiteral as ViewLiteral


view : Value ta (Type ta) -> Html msg
view value =
    case value of
        Value.Literal literalType literal ->
            ViewLiteral.view literal

        Value.List (Type.Reference _ (FQName [ [ "morphir" ], [ "s", "d", "k" ] ] [ [ "list" ] ] [ "list" ]) [ itemType ]) items ->
            ViewList.view itemType items

        _ ->
            Html.span
                [ class "todo"
                , title (Debug.toString value)
                ]
                [ Html.text "???" ]
