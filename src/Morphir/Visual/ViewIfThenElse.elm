module Morphir.Visual.ViewIfThenElse exposing (view)

import Element exposing (Element, column, el, moveRight, spacing, text, wrappedRow)
import Morphir.Graph.GraphViz.PrettyPrint as PrettyPrint
import Morphir.Graph.GraphVizBackend as GraphVizBackend
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value exposing (Value)


view : (Value ta (Type ta) -> Element msg) -> Value ta ( Int, Type ta ) -> Element msg
view viewValue value =
    case GraphVizBackend.mapValue value of
        Just graph ->
            graph
                |> PrettyPrint.mapGraph
                -- TODO: integrate GraphViz custom element
                |> text

        Nothing ->
            text "Cannot display value as decision tree!"
