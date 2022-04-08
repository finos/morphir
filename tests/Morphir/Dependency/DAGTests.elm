module Morphir.Dependency.DAGTests exposing (..)

import Expect
import Morphir.Dependency.DAG as DAG exposing (DAG)
import Set
import Test exposing (Test, describe, test)


depList =
    [ ( "a", [ "b", "c", "e", "k" ] )
    , ( "k", [ "j" ] )
    , ( "u", [] )
    , ( "b", [] )
    , ( "c", [ "f" ] )
    , ( "e", [ "k", "f", "g" ] )
    , ( "j", [] )
    , ( "x", [ "y" ] )
    , ( "f", [] )
    , ( "g", [ "h", "i", "j" ] )
    , ( "h", [] )
    , ( "i", [] )
    ]


buildDagFromList : List ( comparableNode, List comparableNode ) -> Result (DAG.CycleDetected comparableNode) (DAG comparableNode)
buildDagFromList lst =
    lst
        |> List.foldl
            (\( from, edges ) dagSoFar ->
                dagSoFar
                    |> Result.andThen
                        (edges
                            |> Set.fromList
                            |> DAG.insertNode from
                        )
            )
            (Ok DAG.empty)


insertEdgeTests : Test
insertEdgeTests =
    let
        buildGraph : List ( String, String ) -> Result (DAG.CycleDetected String) (DAG String)
        buildGraph edges =
            edges
                |> List.foldl
                    (\( from, to ) soFar ->
                        soFar
                            |> Result.andThen (DAG.insertNode from (Set.singleton to))
                    )
                    (Ok DAG.empty)

        validDAG : String -> List ( String, String ) -> List (List String) -> Test
        validDAG title edges expectedLevels =
            test title
                (\_ ->
                    case buildGraph edges of
                        Ok dag ->
                            dag
                                |> DAG.forwardTopologicalOrdering
                                |> Expect.equal expectedLevels

                        Err error ->
                            Expect.fail (Debug.toString error)
                )

        cycle : String -> List ( String, String ) -> Test
        cycle title edges =
            test title
                (\_ ->
                    case buildGraph edges of
                        Ok _ ->
                            Expect.fail "Should have detected a cycle"

                        Err _ ->
                            Expect.pass
                )
    in
    describe "insertEdge"
        [ validDAG "insert 1"
            [ ( "A", "B" )
            ]
            [ [ "A" ]
            , [ "B" ]
            ]
        , validDAG "insert 2"
            [ ( "A", "B" )
            , ( "A", "C" )
            ]
            [ [ "A" ]
            , [ "B", "C" ]
            ]
        , validDAG "insert 3"
            [ ( "A", "B" )
            , ( "B", "C" )
            ]
            [ [ "A" ]
            , [ "B" ]
            , [ "C" ]
            ]
        , validDAG "insert 4"
            [ ( "A", "B" )
            , ( "C", "A" )
            ]
            [ [ "C" ]
            , [ "A" ]
            , [ "B" ]
            ]
        , validDAG "insert 5"
            [ ( "A", "B" )
            , ( "C", "A" )
            , ( "C", "B" )
            ]
            [ [ "C" ]
            , [ "A" ]
            , [ "B" ]
            ]
        , validDAG "insert 6"
            [ ( "A", "B" )
            , ( "B", "B" )
            ]
            [ [ "A" ]
            , [ "B" ]
            ]
        , validDAG "insert 7"
            [ ( "B", "B" )
            , ( "A", "B" )
            , ( "B", "B" )
            ]
            [ [ "A" ]
            , [ "B" ]
            ]
        , validDAG "insert 8"
            [ ( "A", "B" )
            , ( "B", "B" )
            ]
            [ [ "A" ]
            , [ "B" ]
            ]
        , validDAG "insert 9"
            [ ( "A", "B" )
            , ( "D", "E" )
            , ( "C", "D" )
            , ( "B", "C" )
            ]
            [ [ "A" ]
            , [ "B" ]
            , [ "C" ]
            , [ "D" ]
            , [ "E" ]
            ]
        , validDAG "insert 10"
            [ ( "B", "K" )
            , ( "A", "C" )
            , ( "J", "B" )
            , ( "C", "B" )
            ]
            [ [ "A", "J" ]
            , [ "C" ]
            , [ "B" ]
            , [ "K" ]
            ]
        , cycle "cycle 1"
            [ ( "A", "B" )
            , ( "B", "A" )
            ]
        , cycle "cycle 2"
            [ ( "A", "B" )
            , ( "B", "C" )
            , ( "C", "A" )
            ]
        ]


insertNodeTest : Test
insertNodeTest =
    describe "should insert node"
        [ test "DAG should contain 3 fromNodes"
            (\_ ->
                DAG.insertNode "a" (Set.fromList [ "b", "c" ]) DAG.empty
                    |> Result.withDefault DAG.empty
                    |> DAG.toList
                    |> List.length
                    |> Expect.equal 3
            )
        ]


removeNodeTests : Test
removeNodeTests =
    let
        runTestWithRemoveNode : String -> String -> List (List String) -> Test
        runTestWithRemoveNode title nodeToRemove expected =
            test title
                (\_ ->
                    case buildDagFromList depList of
                        Ok g ->
                            g
                                |> DAG.removeNode nodeToRemove
                                |> DAG.forwardTopologicalOrdering
                                |> Expect.equal expected

                        Err _ ->
                            Expect.fail "CycleDetected Error"
                )
    in
    describe "should remove nodes"
        [ runTestWithRemoveNode "remove 'e' node"
            "e"
            [ [ "a", "g", "u", "x" ]
            , [ "b", "c", "h", "i", "k", "y" ]
            , [ "f", "j" ]
            ]
        , runTestWithRemoveNode "removes 'x' node"
            "x"
            [ [ "a", "u", "y" ]
            , [ "b", "c", "e" ]
            , [ "f", "g", "k" ]
            , [ "h", "i", "j" ]
            ]
        , runTestWithRemoveNode "remove 'j' node"
            "j"
            [ [ "a", "u", "x" ]
            , [ "b", "c", "e", "y" ]
            , [ "f", "g", "k" ]
            , [ "h", "i" ]
            ]
        , runTestWithRemoveNode "remove 'a' node"
            "a"
            [ [ "b", "c", "e", "u", "x" ]
            , [ "f", "g", "k", "y" ]
            , [ "h", "i", "j" ]
            ]
        , runTestWithRemoveNode "no-op: remove 'w' node"
            "w"
            [ [ "a", "u", "x" ]
            , [ "b", "c", "e", "y" ]
            , [ "f", "g", "k" ]
            , [ "h", "i", "j" ]
            ]
        ]


removeEdgeTests : Test
removeEdgeTests =
    let
        runTestWithRemoveEdge : String -> String -> String -> List (List String) -> Test
        runTestWithRemoveEdge title from to expectedResult =
            test title
                (\_ ->
                    case buildDagFromList depList of
                        Ok dag ->
                            dag
                                |> DAG.removeEdge from to
                                |> DAG.forwardTopologicalOrdering
                                |> Expect.equal expectedResult

                        Err _ ->
                            Expect.fail "CycleDetected Error"
                )
    in
    describe "Remove edge"
        [ runTestWithRemoveEdge "should remove edge from 'x' to 'y'"
            "x"
            "y"
            [ [ "a", "u", "x", "y" ]
            , [ "b", "c", "e" ]
            , [ "f", "g", "k" ]
            , [ "h", "i", "j" ]
            ]
        , runTestWithRemoveEdge "should remove edge from 'a' to 'e'"
            "a"
            "e"
            [ [ "a", "e", "u", "x" ]
            , [ "b", "c", "g", "k", "y" ]
            , [ "f", "h", "i", "j" ]
            ]
        , runTestWithRemoveEdge "should remove edge from 'c' to 'f'"
            "c"
            "f"
            [ [ "a", "u", "x" ]
            , [ "b", "c", "e", "y" ]
            , [ "f", "g", "k" ]
            , [ "h", "i", "j" ]
            ]
        , runTestWithRemoveEdge "no-op: no edge from 'c' to 'e'"
            "c"
            "e"
            [ [ "a", "u", "x" ]
            , [ "b", "c", "e", "y" ]
            , [ "f", "g", "k" ]
            , [ "h", "i", "j" ]
            ]
        , runTestWithRemoveEdge "no-op: no edge from 'a' to 'x'"
            "a"
            "x"
            [ [ "a", "u", "x" ]
            , [ "b", "c", "e", "y" ]
            , [ "f", "g", "k" ]
            , [ "h", "i", "j" ]
            ]
        ]


incomingEdgesTests : Test
incomingEdgesTests =
    let
        runTestWithIncomingEdges : String -> String -> List String -> Test
        runTestWithIncomingEdges title node expected =
            test title
                (\_ ->
                    case buildDagFromList depList of
                        Ok g ->
                            g
                                |> DAG.incomingEdges node
                                |> Set.toList
                                |> Expect.equal expected

                        Err _ ->
                            Expect.fail "CycleDetected Error"
                )
    in
    describe "Incoming Edges"
        [ runTestWithIncomingEdges "should return incoming edges for leaf node 'i'"
            "i"
            [ "g" ]
        , runTestWithIncomingEdges "should return incoming edges for leaf node 'h'"
            "h"
            [ "g" ]
        , runTestWithIncomingEdges "should return no incoming edges for root node 'a'"
            "a"
            []
        ]


outgoingEdgeTests : Test
outgoingEdgeTests =
    let
        runTestWithOutgoingEdges : String -> String -> List String -> Test
        runTestWithOutgoingEdges title node expected =
            test title
                (\_ ->
                    case buildDagFromList depList of
                        Ok g ->
                            g
                                |> DAG.outgoingEdges node
                                |> Set.toList
                                |> Expect.equal expected

                        Err _ ->
                            Expect.fail "CycleDetected Error"
                )
    in
    describe "Outgoing Edges"
        [ runTestWithOutgoingEdges "should return no outgoing edges for leaf node 'i'"
            "j"
            []
        , runTestWithOutgoingEdges "should return no outgoing edges for leaf node 'b'"
            "b"
            []
        , runTestWithOutgoingEdges "should return outgoing edges for root node 'a'"
            "a"
            [ "b", "c", "e", "k" ]
        , runTestWithOutgoingEdges "should return outgoing edges for root node 'x'"
            "x"
            [ "y" ]
        , runTestWithOutgoingEdges "should return no outgoing edges for isolated node 'u'"
            "u"
            []
        ]


collectReachableNodesTest : Test
collectReachableNodesTest =
    let
        runTestWithCollectReachableNodesFrom : String -> List ( comparable, List comparable ) -> comparable -> List comparable -> Test
        runTestWithCollectReachableNodesFrom title dagList node expected =
            test title
                (\_ ->
                    buildDagFromList dagList
                        |> Result.withDefault DAG.empty
                        |> DAG.collectForwardReachableNodes node
                        |> Expect.equalSets (Set.fromList expected)
                )
    in
    describe "collectReachableNodesTest"
        [ runTestWithCollectReachableNodesFrom "should collect nodes b,c,d,e,f,i"
            [ ( "a", [ "b", "c" ] )
            , ( "b", [ "d", "e" ] )
            , ( "c", [ "i" ] )
            , ( "d", [ "f" ] )
            ]
            "a"
            [ "b", "c", "d", "e", "i", "f" ]
        , runTestWithCollectReachableNodesFrom "should collect forward reachable nodes from b as d,e,f"
            [ ( "a", [ "b", "c" ] )
            , ( "b", [ "d", "e" ] )
            , ( "c", [ "i" ] )
            , ( "d", [ "f" ] )
            ]
            "b"
            [ "d", "e", "f" ]
        , runTestWithCollectReachableNodesFrom "should collect forward reachable nodes from b as b,d,e,f"
            [ ( "a", [ "b", "c" ] )
            , ( "b", [ "b", "d", "e" ] )
            , ( "c", [ "i" ] )
            , ( "d", [ "f" ] )
            ]
            "b"
            [ "b", "d", "e", "f" ]
        ]
