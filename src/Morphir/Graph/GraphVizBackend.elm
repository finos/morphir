module Morphir.Graph.GraphVizBackend exposing (..)

import Morphir.Graph.GraphViz.AST exposing (Attribute(..), Graph(..), NodeID, Statement(..))
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.Value as Value exposing (Value(..))


mapValue : Value ta ( Int, va ) -> Maybe Graph
mapValue indexedValue =
    case indexedValue of
        Value.IfThenElse ( index, _ ) _ _ _ ->
            Just
                (Digraph (String.concat [ "graph_", String.fromInt index ])
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
            [ NodeStatement (valueToID indexedValue)
                [ Attribute "label" (valueToLabel indexedValue)
                , Attribute "shape" "box"
                ]
            ]


valueEdges : Value ta ( Int, va ) -> List Statement
valueEdges indexedValue =
    case indexedValue of
        Value.IfThenElse ( index, _ ) _ thenBranch elseBranch ->
            let
                conditionID =
                    indexToNodeID index
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


valueToID : Value ta ( Int, va ) -> String
valueToID value =
    value
        |> Value.valueAttribute
        |> Tuple.first
        |> indexToNodeID


indexToNodeID : Int -> NodeID
indexToNodeID index =
    String.concat
        [ "node_"
        , String.fromInt index
        ]


valueToLabel : Value ta ( Int, va ) -> String
valueToLabel indexedValue =
    case indexedValue of
        Value.Literal _ literal ->
            case literal of
                BoolLiteral bool ->
                    if bool == True then
                        "True"

                    else
                        "False"

                CharLiteral char ->
                    String.fromChar char

                StringLiteral string ->
                    string

                IntLiteral int ->
                    String.fromInt int

                FloatLiteral float ->
                    String.fromFloat float

        Value.Variable _ name ->
            String.concat name

        Value.Apply _ fun arg ->
            case Value.uncurryApply fun arg of
                ( Value.Reference _ (FQName [ [ "morphir" ], [ "s", "d", "k" ] ] moduleName localName), [ argValue1, argValue2 ] ) ->
                    let
                        functionName : String
                        functionName =
                            String.join "."
                                [ moduleName |> Path.toString Name.toTitleCase "."
                                , localName |> Name.toCamelCase
                                ]

                        operatorName : String
                        operatorName =
                            case functionName of
                                "Basics.equal" ->
                                    "="

                                _ ->
                                    localName |> Name.toHumanWords |> String.join " "
                    in
                    String.concat [ valueToLabel argValue1, " ", operatorName, " ", valueToLabel argValue2 ]

                _ ->
                    "?"

        _ ->
            "?"
