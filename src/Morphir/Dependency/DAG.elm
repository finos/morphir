module Morphir.Dependency.DAG exposing
    ( DAG, CycleDetected
    , empty, insertEdge
    , incomingEdges, outgoingEdges
    , forwardTopologicalOrdering, backwardTopologicalOrdering
    )

{-| This module implements a DAG (Directed Acyclic Graph) data structure with efficient topological ordering and cycle
detection capabilities. It's designed to be used in an incremental fashion. Adding an edge that forms a cycle will
immediately report an error. If there is no cycle the edge is inserted into the right level based on partial ordering.
This level can be used either to derive a topological ordering or to process in parallel as much as dependencies allow.

@docs DAG, CycleDetected


# Building the graph

@docs empty, insertEdge


# Querying

@docs incomingEdges, outgoingEdges


# Ordering

@docs forwardTopologicalOrdering, backwardTopologicalOrdering

-}

import Dict exposing (Dict)
import Set exposing (Set)


{-| Type to store the DAG. Internally it keeps track of each node in a dictionary together with the outgoing edges and
the level they are at in the partial ordering.
-}
type alias DAG comparableNode =
    Dict comparableNode ( Set comparableNode, Int )


{-| The error that's reported when a cycle is detected in the graph.
-}
type CycleDetected
    = CycleDetected


{-| Creates an empty DAG with no nodes or edges.
-}
empty : DAG comparableNode
empty =
    Dict.empty


{-| Inserts an edge defined by the from and to nodes. Returns an error if a cycle would be formed by the edge.
This design makes sure that a DAG cannot possibly have cycles in it since there is no way to create such a DAG.
-}
insertEdge : comparableNode -> comparableNode -> DAG comparableNode -> Result CycleDetected (DAG comparableNode)
insertEdge from to graph =
    let
        shiftTransitively : Int -> comparableNode -> DAG comparableNode -> DAG comparableNode
        shiftTransitively by n g =
            case g |> Dict.get n of
                Just ( toNodes, level ) ->
                    toNodes
                        |> Set.foldl (shiftTransitively by)
                            (g |> Dict.insert n ( toNodes, level + by ))

                Nothing ->
                    g

        shiftAll : Int -> DAG comparableNode -> DAG comparableNode
        shiftAll by g =
            g |> Dict.map (\_ ( toNodes, level ) -> ( toNodes, level + by ))
    in
    case graph |> Dict.get to of
        Just ( toEdges, toLevel ) ->
            if toEdges |> Set.member from then
                Err CycleDetected

            else
                case graph |> Dict.get from of
                    Just ( fromEdges, fromLevel ) ->
                        if fromEdges |> Set.member to then
                            -- duplicate edge, ignore
                            Ok graph

                        else if fromLevel < toLevel then
                            Ok
                                (graph
                                    |> Dict.insert from ( fromEdges |> Set.insert to, fromLevel )
                                )

                        else if fromLevel == toLevel then
                            Ok
                                (graph
                                    |> Dict.insert from ( fromEdges |> Set.insert to, fromLevel )
                                    |> shiftTransitively 1 to
                                )

                        else
                            Err CycleDetected

                    Nothing ->
                        Ok
                            (if toLevel == 0 then
                                graph
                                    |> shiftAll 1
                                    |> Dict.insert from ( Set.singleton to, 0 )

                             else
                                graph
                                    |> Dict.insert from ( Set.singleton to, toLevel - 1 )
                            )

        Nothing ->
            case graph |> Dict.get from of
                Just ( fromEdges, fromLevel ) ->
                    Ok
                        (graph
                            |> Dict.insert from ( fromEdges |> Set.insert to, fromLevel )
                            |> Dict.insert to ( Set.empty, fromLevel + 1 )
                        )

                Nothing ->
                    Ok
                        (graph
                            |> Dict.insert from ( Set.singleton to, 0 )
                            |> Dict.insert to ( Set.empty, 1 )
                        )


outgoingEdges : comparableNode -> DAG comparableNode -> Set comparableNode
outgoingEdges fromNode dag =
    dag
        |> Dict.get fromNode
        |> Maybe.map (\( toNodes, _ ) -> toNodes)
        |> Maybe.withDefault Set.empty


incomingEdges : comparableNode -> DAG comparableNode -> Set comparableNode
incomingEdges toNode dag =
    dag
        |> Dict.toList
        |> List.filterMap
            (\( fromNode, ( toNodes, _ ) ) ->
                if Set.member toNode toNodes then
                    Just fromNode

                else
                    Nothing
            )
        |> Set.fromList


forwardTopologicalOrdering : DAG comparableNode -> List (List comparableNode)
forwardTopologicalOrdering dag =
    let
        dagList : List ( comparableNode, ( Set comparableNode, Int ) )
        dagList =
            dag
                |> Dict.toList

        maxLevel : Int
        maxLevel =
            dagList
                |> List.map (\( _, ( _, level ) ) -> level)
                |> List.maximum
                |> Maybe.withDefault 0
    in
    List.range 0 maxLevel
        |> List.map
            (\level ->
                dagList
                    |> List.filterMap
                        (\( fromNode, ( _, fromNodeLevel ) ) ->
                            if fromNodeLevel == level then
                                Just fromNode

                            else
                                Nothing
                        )
            )


backwardTopologicalOrdering : DAG comparableNode -> List (List comparableNode)
backwardTopologicalOrdering dag =
    forwardTopologicalOrdering dag |> List.reverse


levels : DAG comparableNode -> Dict comparableNode Int
levels dag =
    dag
        |> Dict.map (\_ ( _, level ) -> level)
