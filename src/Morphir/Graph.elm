module Morphir.Graph exposing (Graph, empty, fromList, isEmpty, reachableNodes, topologicalSort)

import Dict exposing (Dict)
import Set exposing (Set)


type Graph node comparable
    = Graph (List ( node, comparable, Set comparable ))


fromList : List ( node, comparable, List comparable ) -> Graph node comparable
fromList list =
    list
        |> List.map (\( node, fromKey, toKeys ) -> ( node, fromKey, Set.fromList toKeys ))
        |> Graph


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
