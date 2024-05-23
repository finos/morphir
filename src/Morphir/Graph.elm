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


module Morphir.Graph exposing (Graph, empty, fromList, isEmpty, nodeLabels, reachableNodes, topologicalSort)

import Set exposing (Set)


type Graph node comparable
    = Graph (List ( node, comparable, Set comparable ))


fromList : List ( node, comparable, List comparable ) -> Graph node comparable
fromList list =
    list
        |> List.map (\( node, fromKey, toKeys ) -> ( node, fromKey, Set.fromList toKeys ))
        |> Graph


nodeLabels : Graph node comparable -> Set comparable
nodeLabels (Graph startNodeList) =
    startNodeList
        |> List.concatMap
            (\( _, startLabel, endLabels ) ->
                startLabel :: Set.toList endLabels
            )
        |> Set.fromList


empty : Graph node comparable
empty =
    Graph []


isEmpty : Graph node comparable -> Bool
isEmpty (Graph edges) =
    List.isEmpty edges


topologicalSort : Graph node comparable -> ( List comparable, Graph node comparable )
topologicalSort (Graph edges) =
    let
        normalize : List ( node, comparable, Set comparable ) -> List ( node, comparable, Set comparable )
        normalize graphEdges =
            let
                toNodes =
                    graphEdges
                        |> List.map (\( _, _, toKeys ) -> toKeys)
                        |> List.foldl Set.union Set.empty

                fromNodes =
                    graphEdges
                        |> List.map (\( _, fromKey, _ ) -> fromKey)
                        |> Set.fromList

                emptyFromNodes =
                    Set.diff toNodes fromNodes
                        |> Set.toList
                        |> List.concatMap
                            (\fromKey ->
                                graphEdges
                                    |> List.filterMap
                                        (\( node, key, _ ) ->
                                            if key == fromKey then
                                                Just ( node, fromKey, Set.empty )

                                            else
                                                Nothing
                                        )
                            )
            in
            graphEdges ++ emptyFromNodes

        step : List ( node, comparable, Set comparable ) -> List comparable -> ( List comparable, Graph node comparable )
        step graphEdges sorting =
            let
                toNodes =
                    graphEdges
                        |> List.map (\( _, _, toKeys ) -> toKeys)
                        |> List.foldl Set.union Set.empty

                fromNodes =
                    graphEdges
                        |> List.map (\( _, fromKey, _ ) -> fromKey)
                        |> Set.fromList

                startNodes =
                    Set.diff fromNodes toNodes
            in
            case startNodes |> Set.toList |> List.head of
                Just startNode ->
                    let
                        newGraphEdges =
                            graphEdges
                                |> List.filter
                                    (\( _, fromKey, _ ) ->
                                        fromKey /= startNode
                                    )
                    in
                    step newGraphEdges (startNode :: sorting)

                Nothing ->
                    ( List.reverse sorting, Graph graphEdges )
    in
    step (normalize edges) []


reachableNodes : Set comparable -> Graph node comparable -> Set comparable
reachableNodes startNodes (Graph edges) =
    let
        directlyReachable : Set comparable -> Set comparable
        directlyReachable fromNodes =
            edges
                |> List.filterMap
                    (\( _, fromNode, toNodes ) ->
                        if fromNodes |> Set.member fromNode then
                            Just toNodes

                        else
                            Nothing
                    )
                |> List.foldl Set.union Set.empty

        transitivelyReachable : Set comparable -> Set comparable
        transitivelyReachable fromNodes =
            if Set.isEmpty fromNodes then
                Set.empty

            else
                let
                    reachables =
                        Set.union (directlyReachable fromNodes) fromNodes
                in
                if reachables == fromNodes then
                    fromNodes

                else
                    Set.union fromNodes (transitivelyReachable reachables)
    in
    transitivelyReachable startNodes
