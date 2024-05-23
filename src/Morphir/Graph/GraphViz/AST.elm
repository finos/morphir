module Morphir.Graph.GraphViz.AST exposing (..)

{-| This is an AST for the DOT language as described [in this grammar](https://graphviz.org/doc/info/lang.html).
-}


type Graph
    = Digraph GraphID (List Statement)


type alias GraphID =
    String


type alias NodeID =
    String


type Statement
    = NodeStatement NodeID (List Attribute)
    | EdgeStatement NodeID NodeID (List Attribute)


type Attribute
    = Attribute String String
