module Morphir.Graph.GraphViz.PrettyPrint exposing (..)

import Morphir.File.SourceCode exposing (Doc, concat, empty, indentLines, newLine)
import Morphir.Graph.GraphViz.AST exposing (Attribute(..), Graph(..), Statement(..))


mapGraph : Graph -> Doc
mapGraph graph =
    case graph of
        Digraph id statements ->
            concat
                [ concat [ "digraph ", id, " {", newLine ]
                , statements
                    |> List.map
                        (\stmnt ->
                            concat [ mapStatement stmnt, ";", newLine ]
                        )
                    |> indentLines 2
                , "}"
                ]


mapStatement : Statement -> Doc
mapStatement stmnt =
    case stmnt of
        NodeStatement nodeId attributes ->
            concat [ nodeId, mapAttributes attributes ]

        EdgeStatement fromNode toNode attributes ->
            concat [ fromNode, " -> ", toNode, mapAttributes attributes ]


mapAttributes : List Attribute -> Doc
mapAttributes attributes =
    if List.isEmpty attributes then
        empty

    else
        let
            attrDoc =
                attributes
                    |> List.map
                        (\(Attribute key value) ->
                            concat [ key, "=\"", value, "\"" ]
                        )
                    |> List.intersperse ", "
                    |> concat
        in
        concat [ "[", attrDoc, "]" ]
