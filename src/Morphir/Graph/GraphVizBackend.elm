module Morphir.Graph.GraphVizBackend exposing (..)

import Dict exposing (Dict)
import Morphir.Graph.GraphViz.AST exposing (Attribute(..), Graph(..), NodeID, Statement(..))
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.Value as Value exposing (Value(..))


mapValue : Value ta ( Int, va ) -> Dict Name (Value () ()) -> Maybe Graph
mapValue indexedValue variables =
    case ignoreWrapperValues indexedValue of
        Value.IfThenElse ( index, _ ) _ _ _ ->
            Just
                (Digraph (String.concat [ "graph_", String.fromInt index ])
                    (List.concat
                        [ valueNodes indexedValue variables
                        , valueEdges indexedValue
                        ]
                    )
                )

        _ ->
            Nothing


valueNodes : Value ta ( Int, va ) -> Dict Name (Value () ()) -> List Statement
valueNodes indexedValue variables =
    case ignoreWrapperValues indexedValue of
        Value.IfThenElse ( index, _ ) condition thenBranch elseBranch ->
            let
                conditionNode : Statement
                conditionNode =
                    NodeStatement (indexToNodeID index)
                        [ Attribute "label" (valueToLabel (condition |> Value.mapValueAttributes (always ()) (always ())) variables)
                        , Attribute "shape" "diamond"
                        ]
            in
            List.concat
                [ [ conditionNode ]
                , valueNodes thenBranch variables
                , valueNodes elseBranch variables
                ]

        _ ->
            [ NodeStatement (valueToID indexedValue)
                [ Attribute "label" (valueToLabel (indexedValue |> Value.mapValueAttributes (always ()) (always ())) variables)
                , Attribute "shape" "box"
                ]
            ]


valueEdges : Value ta ( Int, va ) -> List Statement
valueEdges indexedValue =
    case ignoreWrapperValues indexedValue of
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


ignoreWrapperValues : Value ta va -> Value ta va
ignoreWrapperValues value =
    case value of
        Value.LetDefinition _ _ _ inValue ->
            ignoreWrapperValues inValue

        _ ->
            value


valueToID : Value ta ( Int, va ) -> String
valueToID value =
    ignoreWrapperValues value
        |> Value.valueAttribute
        |> Tuple.first
        |> indexToNodeID


indexToNodeID : Int -> NodeID
indexToNodeID index =
    String.concat
        [ "node_"
        , String.fromInt index
        ]


valueToLabel : Value () () -> Dict Name (Value () ()) -> String
valueToLabel indexedValue variables =
    case ignoreWrapperValues indexedValue of
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
                    String.concat [ "'", string, "'" ]

                WholeNumberLiteral int ->
                    String.fromInt int

                FloatLiteral float ->
                    String.fromFloat float

        Value.Variable _ name ->
            let
                suffix =
                    case variables |> Dict.get name of
                        Just varValue ->
                            String.concat [ " (", valueToLabel varValue variables, ")" ]

                        Nothing ->
                            ""
            in
            String.concat [ name |> Name.toHumanWords |> String.join " ", suffix ]

        Value.Apply _ fun arg ->
            case Value.uncurryApply fun arg of
                ( Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], moduleName, localName ), [ argValue1 ] ) ->
                    let
                        functionName : String
                        functionName =
                            String.join "."
                                [ moduleName |> Path.toString Name.toTitleCase "."
                                , localName |> Name.toCamelCase
                                ]

                        operatorName : String
                        operatorName =
                            case unaryFunctionSymbols |> Dict.get functionName of
                                Just symbol ->
                                    symbol

                                _ ->
                                    localName |> Name.toHumanWords |> String.join " "
                    in
                    String.join " " [ operatorName, valueToLabel argValue1 variables ]

                ( Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], moduleName, localName ), [ argValue1, argValue2 ] ) ->
                    let
                        functionName : String
                        functionName =
                            String.join "."
                                [ moduleName |> Path.toString Name.toTitleCase "."
                                , localName |> Name.toCamelCase
                                ]

                        operatorName : String
                        operatorName =
                            case binaryFunctionSymbols |> Dict.get functionName of
                                Just symbol ->
                                    symbol

                                _ ->
                                    localName |> Name.toHumanWords |> String.join " "
                    in
                    String.join " " [ valueToLabel argValue1 variables, operatorName, valueToLabel argValue2 variables ]

                _ ->
                    "?"

        _ ->
            "?"


unaryFunctionSymbols : Dict String String
unaryFunctionSymbols =
    Dict.fromList
        [ ( "Basics.negate", "-" )
        ]


binaryFunctionSymbols : Dict String String
binaryFunctionSymbols =
    Dict.fromList
        [ ( "Basics.add", "+" )
        , ( "Basics.subtract", "-" )
        , ( "Basics.multiply", "*" )
        , ( "Basics.divide", "/" )
        , ( "Basics.integerDivide", "/" )
        , ( "Basics.equal", "=" )
        , ( "Basics.notEqual", "≠" )
        , ( "Basics.lessThan", "<" )
        , ( "Basics.greaterThan", ">" )
        , ( "Basics.lessThanOrEqual", "≤" )
        , ( "Basics.greaterThanOrEqual", "≥" )
        ]
