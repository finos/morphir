module Morphir.Graph.GraphVizBackend exposing (..)

import Morphir.Graph.GraphViz.AST exposing (Graph(..))
import Morphir.IR.Value as Value exposing (Value)


mapValue : Value ta va -> Maybe Graph
mapValue value =
    case value of
        Value.IfThenElse _ cond thenBranch elseBranch ->
            Just
                (Digraph "foo"
                    [-- TODO: generate nodes and edges
                    ]
                )

        _ ->
            Nothing
