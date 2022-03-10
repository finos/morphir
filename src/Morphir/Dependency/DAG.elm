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
    { edges : Dict comparableNode ( Set comparableNode, Int )
    , orphanNodes : Set comparableNode
    }


{-| The error that's reported when a cycle is detected in the graph.
-}
type CycleDetected
    = CycleDetected


{-| Creates an empty DAG with no nodes or edges.
-}
empty : DAG comparableNode
empty =
    { edges = Dict.empty
    , orphanNodes = Set.empty
    }


{-| Inserts an edge defined by the from and to nodes. Returns an error if a cycle would be formed by the edge.
This design makes sure that a DAG cannot possibly have cycles in it since there is no way to create such a DAG.
-}
insertEdge : comparableNode -> comparableNode -> DAG comparableNode -> Result CycleDetected (DAG comparableNode)
insertEdge from to graph =
    let
        shiftTransitively : Int -> comparableNode -> DAG comparableNode -> DAG comparableNode
        shiftTransitively by n g =
            case g.edges |> Dict.get n of
                Just ( toNodes, level ) ->
                    toNodes
                        |> Set.foldl (shiftTransitively by)
                            { g | edges = g.edges |> Dict.insert n ( toNodes, level + by ) }

                Nothing ->
                    g

        shiftAll : Int -> DAG comparableNode -> DAG comparableNode
        shiftAll by g =
            { g | edges = g.edges |> Dict.map (\_ ( toNodes, level ) -> ( toNodes, level + by )) }

        removeFromOrphan : comparableNode -> Set comparableNode -> Set comparableNode
        removeFromOrphan node orphanNodes =
            if orphanNodes |> Set.member node then
                orphanNodes |> Set.remove node

            else
                orphanNodes
    in
    case graph.edges |> Dict.get to of
        Just ( toEdges, toLevel ) ->
            if toEdges |> Set.member from then
                Err CycleDetected

            else
                case graph.edges |> Dict.get from of
                    Just ( fromEdges, fromLevel ) ->
                        if fromEdges |> Set.member to then
                            -- duplicate edge, ignore
                            Ok graph

                        else if fromLevel < toLevel then
                            Ok
                                { graph
                                    | edges =
                                        graph.edges
                                            |> Dict.insert from ( fromEdges |> Set.insert to, fromLevel )
                                    , orphanNodes = removeFromOrphan from graph.orphanNodes
                                }

                        else if fromLevel == toLevel then
                            { graph
                                | edges =
                                    graph.edges
                                        |> Dict.insert from ( fromEdges |> Set.insert to, fromLevel )
                                , orphanNodes = removeFromOrphan from graph.orphanNodes
                            }
                                |> shiftTransitively 1 to
                                |> Ok

                        else
                            Err CycleDetected

                    Nothing ->
                        Ok
                            (if toLevel == 0 then
                                graph
                                    |> shiftAll 1
                                    |> (\g ->
                                            { g
                                                | edges = Dict.insert from ( Set.singleton to, 0 ) g.edges
                                                , orphanNodes = removeFromOrphan from graph.orphanNodes
                                            }
                                       )

                             else
                                { graph
                                    | edges =
                                        graph.edges
                                            |> Dict.insert from ( Set.singleton to, toLevel - 1 )
                                    , orphanNodes = removeFromOrphan from graph.orphanNodes
                                }
                            )

        Nothing ->
            case graph.edges |> Dict.get from of
                Just ( fromEdges, fromLevel ) ->
                    Ok
                        { graph
                            | edges =
                                graph.edges
                                    |> Dict.insert from ( fromEdges |> Set.insert to, fromLevel )
                                    |> Dict.insert to ( Set.empty, fromLevel + 1 )
                            , orphanNodes = removeFromOrphan from graph.orphanNodes
                        }

                Nothing ->
                    Ok
                        { graph
                            | edges =
                                graph.edges
                                    |> Dict.insert from ( Set.singleton to, 0 )
                                    |> Dict.insert to ( Set.empty, 1 )
                            , orphanNodes = removeFromOrphan from graph.orphanNodes
                        }


{-| Insert node without edges. Inserts node into orphan nodes set if the from node is already not in the edges
-}
insertNode : comparableNode -> Set comparableNode -> DAG comparableNode -> Result CycleDetected (DAG comparableNode)
insertNode fromNode toNodes dag =
    let
        insertEdges : DAG comparableNode -> Result CycleDetected (DAG comparableNode)
        insertEdges d =
            Set.toList toNodes
                |> List.foldl
                    (\toNode dagResultSoFar ->
                        Result.andThen (insertEdge fromNode toNode) dagResultSoFar
                    )
                    (Ok d)

        insertIntoOrphanNodes : DAG comparableNode -> DAG comparableNode
        insertIntoOrphanNodes d =
            { d | orphanNodes = Set.insert fromNode dag.orphanNodes }
    in
    case dag.edges |> Dict.get fromNode of
        Just ( _, _ ) ->
            dag |> insertEdges

        Nothing ->
            dag |> insertIntoOrphanNodes |> insertEdges


{-| Get the outgoing edges of a given node in the graph in the form of a set of nodes that the edges point to.

    graph =
        empty
            |> insertEdge 1 2
            |> insertEdge 2 3
            |> insertEdge 2 4

    graph |> outgoingEdges 1 == Set.fromList [ 2 ]
    graph |> outgoingEdges 2 == Set.fromList [ 3, 4 ]
    graph |> outgoingEdges 3 == Set.empty

-}
outgoingEdges : comparableNode -> DAG comparableNode -> Set comparableNode
outgoingEdges fromNode dag =
    dag.edges
        |> Dict.get fromNode
        |> Maybe.map (\( toNodes, _ ) -> toNodes)
        |> Maybe.withDefault Set.empty


{-| Get the incoming edges of a given node in the graph in the form of a set of nodes that the edges point from.

    graph =
        empty
            |> insertEdge 1 2
            |> insertEdge 2 3
            |> insertEdge 2 4
            |> insertEdge 4 3

    graph |> incomingEdges 1 == Set.empty
    graph |> incomingEdges 2 == Set.fromList [ 1 ]
    graph |> incomingEdges 3 == Set.fromList [ 2, 4 ]

-}
incomingEdges : comparableNode -> DAG comparableNode -> Set comparableNode
incomingEdges toNode dag =
    dag.edges
        |> Dict.toList
        |> List.filterMap
            (\( fromNode, ( toNodes, _ ) ) ->
                if Set.member toNode toNodes then
                    Just fromNode

                else
                    Nothing
            )
        |> Set.fromList


{-| Get a topological ordering (see <https://en.wikipedia.org/wiki/Directed_acyclic_graph#Topological_sorting_and_recognition>)
of the nodes in the graph where the ordering follows the direction of the edges. The result is a list of lists of nodes
because some nodes are not connected by any path so they have no specific ordering therefore we put them on the same
level.

    graph =
        empty
            |> insertEdge 1 2
            |> insertEdge 2 3
            |> insertEdge 2 4
            |> insertEdge 4 5

    forwardTopologicalOrdering graph ==
        [ [ 1 ]
        , [ 2 ]
        , [ 3, 4 ]
        , [ 5 ]
        ]

-}
forwardTopologicalOrdering : DAG comparableNode -> List (List comparableNode)
forwardTopologicalOrdering dag =
    let
        dagList : List ( comparableNode, ( Set comparableNode, Int ) )
        dagList =
            dag.edges
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


{-| Get a topological ordering (see <https://en.wikipedia.org/wiki/Directed_acyclic_graph#Topological_sorting_and_recognition>)
of the nodes in the graph where the ordering is the opposite of the direction of the edges. The result is a list of
lists of nodes because some nodes are not connected by any path so they have no specific ordering therefore we put them
on the same level.

    graph =
        empty
            |> insertEdge 1 2
            |> insertEdge 2 3
            |> insertEdge 2 4
            |> insertEdge 4 5

    forwardTopologicalOrdering graph ==
        [ [ 5 ]
        , [ 3, 4 ]
        , [ 2 ]
        , [ 1 ]
        ]

-}
backwardTopologicalOrdering : DAG comparableNode -> List (List comparableNode)
backwardTopologicalOrdering dag =
    forwardTopologicalOrdering dag |> List.reverse
