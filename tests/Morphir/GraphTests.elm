module Morphir.GraphTests exposing (..)

import Expect
import Morphir.Graph as Graph
import Set
import Test exposing (..)


topologicalSortTests : Test
topologicalSortTests =
    describe "topologicalSort"
        [ test "empty graph is sorted" <|
            \_ ->
                Graph.topologicalSort Graph.empty
                    |> Expect.equal ( [], Graph.empty )
        ]


reachableNodesTests : Test
reachableNodesTests =
    describe "reachableNodes"
        [ test "empty graph returns empty" <|
            \_ ->
                Graph.reachableNodes Set.empty Graph.empty
                    |> Expect.equal Set.empty
        , test "unreachable node removed" <|
            \_ ->
                Graph.fromList [ ( "1", 1, [ 2 ] ), ( "2", 2, [ 3 ] ), ( "4", 4, [ 5 ] ) ]
                    |> Graph.reachableNodes (Set.fromList [ 1 ])
                    |> Expect.equal (Set.fromList [ 1, 2, 3 ])
        , test "cycles handled gracefully" <|
            \_ ->
                Graph.fromList [ ( "1", 1, [ 2 ] ), ( "2", 2, [ 1 ] ), ( "4", 4, [ 5 ] ) ]
                    |> Graph.reachableNodes (Set.fromList [ 1 ])
                    |> Expect.equal (Set.fromList [ 1, 2 ])
        ]
