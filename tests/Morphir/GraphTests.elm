module Morphir.GraphTests exposing (..)

{-
Copyright 2020 Morgan Stanley

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}


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
