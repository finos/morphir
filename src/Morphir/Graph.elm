module Morphir.Graph exposing (Graph, empty, fromDict, fromList, isEmpty, reachableNodes, topologicalSort)

import Dict exposing (Dict)
import Set exposing (Set)


type Graph comparable
    = Graph (Dict comparable (Set comparable))


fromDict : Dict comparable (Set comparable) -> Graph comparable
fromDict =
    Graph


fromList : List ( comparable, List comparable ) -> Graph comparable
fromList list =
    list
        |> List.map (\( from, tos ) -> ( from, Set.fromList tos ))
        |> Dict.fromList
        |> Graph


empty : Graph comparable
empty =
    Graph Dict.empty


isEmpty : Graph comparable -> Bool
isEmpty (Graph edges) =
    Dict.isEmpty edges


topologicalSort : Graph comparable -> ( List comparable, Graph comparable )
topologicalSort (Graph edges) =
    let
        normalize graphEdges =
            let
                toNodes =
                    graphEdges
                        |> Dict.values
                        |> List.foldl Set.union Set.empty

                fromNodes =
                    graphEdges
                        |> Dict.keys
                        |> Set.fromList

                emptyFromNodes =
                    Set.diff toNodes fromNodes
                        |> Set.toList
                        |> List.map
                            (\from ->
                                ( from, Set.empty )
                            )
                        |> Dict.fromList
            in
            Dict.union graphEdges emptyFromNodes

        step graphEdges sorting =
            let
                toNodes =
                    graphEdges
                        |> Dict.values
                        |> List.foldl Set.union Set.empty

                fromNodes =
                    graphEdges
                        |> Dict.keys
                        |> Set.fromList

                startNodes =
                    Set.diff fromNodes toNodes
            in
            case startNodes |> Set.toList |> List.head of
                Just startNode ->
                    let
                        newGraphEdges =
                            graphEdges
                                |> Dict.toList
                                |> List.filter
                                    (\( from, tos ) ->
                                        from /= startNode
                                    )
                                |> Dict.fromList
                    in
                    step newGraphEdges (startNode :: sorting)

                Nothing ->
                    ( List.reverse sorting, Graph graphEdges )
    in
    step (normalize edges) []


reachableNodes : Set comparable -> Graph comparable -> Set comparable
reachableNodes startNodes (Graph edges) =
    let
        directlyReachable : Set comparable -> Set comparable
        directlyReachable fromNodes =
            edges
                |> Dict.toList
                |> List.filterMap
                    (\( fromNode, toNodes ) ->
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
