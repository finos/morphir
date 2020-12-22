module Morphir.Graph.GraphVizBackend exposing (..)

import Morphir.Graph.GraphViz.AST exposing (Attribute(..), Graph(..), NodeID, Statement(..))
import Morphir.IR.Value as Value exposing (Value)


mapValue : Value ta ( Int, va ) -> Maybe Graph
mapValue indexedValue =
    case indexedValue of
        Value.IfThenElse ( index, _ ) _ _ _ ->
            Just
                (Digraph (String.concat [ "graph-", String.fromInt index ])
                    (List.concat
                        [ valueNodes indexedValue
                        , valueEdges indexedValue
                        ]
                    )
                )

        _ ->
            Nothing


valueNodes : Value ta ( Int, va ) -> List Statement
valueNodes indexedValue =
    case indexedValue of
        Value.IfThenElse ( index, _ ) condition thenBranch elseBranch ->
            let
                conditionNode : Statement
                conditionNode =
                    NodeStatement (indexToNodeID index)
                        [ Attribute "label" (valueToLabel condition)
                        , Attribute "shape" "diamond"
                        ]
            in
            List.concat
                [ [ conditionNode ]
                , valueNodes thenBranch
                , valueNodes elseBranch
                ]

        _ ->
            []


valueEdges : Value ta ( Int, va ) -> List Statement
valueEdges indexedValue =
    case indexedValue of
        Value.IfThenElse ( index, _ ) _ thenBranch elseBranch ->
            let
                conditionID =
                    indexToNodeID index

                valueToID value =
                    value
                        |> Value.valueAttribute
                        |> Tuple.first
                        |> indexToNodeID
            in
            List.concat
                [ [ EdgeStatement conditionID
                        (valueToID thenBranch)
                        [ Attribute "label" "Yes"
                        ]
                  , EdgeStatement conditionID
                        (valueToID elseBranch)
                        [ Attribute "label" "No"
                        ]
                  ]
                , valueEdges thenBranch
                , valueEdges elseBranch
                ]

        _ ->
            []


indexToNodeID : Int -> NodeID
indexToNodeID index =
    String.concat
        [ "node-"
        , String.fromInt index
        ]


valueToLabel : Value ta ( Int, va ) -> String
valueToLabel indexedValue =
    "?"
