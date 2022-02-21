module Morphir.Dependency.DAGTests exposing (..)

import Dict
import Expect
import Morphir.Dependency.DAG as DAG exposing (DAG)
import Test exposing (Test, describe, test)


insertEdgeTests : Test
insertEdgeTests =
    let
        buildGraph : List ( String, String ) -> Result DAG.CycleDetected (DAG String)
        buildGraph edges =
            edges
                |> List.foldl
                    (\( from, to ) soFar ->
                        soFar
                            |> Result.andThen (DAG.insertEdge from to)
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
