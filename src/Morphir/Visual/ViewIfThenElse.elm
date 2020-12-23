module Morphir.Visual.ViewIfThenElse exposing (view)

import Element exposing (Element, column, el, html, moveRight, spacing, text, wrappedRow)
import Html
import Html.Attributes exposing (attribute)
import Morphir.File.SourceCode exposing (Doc)
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
                |> graphToNode

        Nothing ->
            text "Cannot display value as decision tree!"


graphToNode : Doc -> Element msg
graphToNode dotStructure =
    Html.node "if-then-else"
        [ attribute "dotStructure" dotStructure
        ]
        []
        |> html
