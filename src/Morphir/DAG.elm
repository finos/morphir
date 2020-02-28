module Morphir.DAG exposing (DAG, fromDict, isEmpty, topologicalSort)

import Dict exposing (Dict)
import Set exposing (Set)


type DAG comparable
    = DAG (Dict comparable (Set comparable))


fromDict : Dict comparable (Set comparable) -> DAG comparable
fromDict =
    DAG


isEmpty : DAG comparable -> Bool
isEmpty (DAG edges) =
    Dict.isEmpty edges


topologicalSort : DAG comparable -> ( List comparable, DAG comparable )
topologicalSort (DAG edges) =
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
                    ( List.reverse sorting, DAG graphEdges )
    in
    step (normalize edges) []
