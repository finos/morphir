module Morphir.Dependency.DAG exposing
    ( DAG, CycleDetected(..)
    , empty, insertEdge
    , incomingEdges, outgoingEdges
    , forwardTopologicalOrdering, backwardTopologicalOrdering
    , toList
    , insertNode, removeEdge, removeNode
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


# Transforming

@docs toList

-}

import Dict as Dict exposing (Dict)
import Set as Set exposing (Set)


{-| Type to store the DAG. Internally it keeps track of each comparableNode

in a dictionary together with the outgoing edges and
the level they are at in the partial ordering.

-}
type DAG comparableNode
    = DAG (Dict comparableNode (Set comparableNode))


{-| The error that's reported when a cycle is detected in the graph.
-}
type CycleDetected comparableNode
    = CycleDetected comparableNode comparableNode


{-| Creates an empty DAG with no nodes or edges.
-}
empty : DAG comparableNode
empty =
    DAG Dict.empty


{-| Inserts an edge defined by the from and to nodes. Returns an error if a cycle would be formed by the edge.
This design makes sure that a DAG cannot possibly have cycles in it since there is no way to create such a DAG.
-}
insertEdge : comparableNode -> comparableNode -> DAG comparableNode -> Result (CycleDetected comparableNode) (DAG comparableNode)
insertEdge from to (DAG edgesByNodes) =
    if from == to then
        case edgesByNodes |> Dict.get from of
            Just fromEdges ->
                edgesByNodes
                    |> Dict.insert from (fromEdges |> Set.insert to)
                    |> DAG
                    |> Ok

            Nothing ->
                edgesByNodes
                    |> Dict.insert from (Set.singleton to)
                    |> DAG
                    |> Ok

    else
        case edgesByNodes |> Dict.get to of
            Just toEdges ->
                if toEdges |> Set.member from then
                    -- TODO recursively find cycles
                    Err (CycleDetected from to)

                else
                    case edgesByNodes |> Dict.get from of
                        Just fromEdges ->
                            if fromEdges |> Set.member to then
                                -- duplicate edge, ignore
                                DAG edgesByNodes |> Ok

                            else
                                -- TODO recursively find cycles
                                edgesByNodes
                                    |> Dict.insert from (fromEdges |> Set.insert to)
                                    |> DAG
                                    |> Ok

                        Nothing ->
                            Ok
                                (edgesByNodes
                                    |> Dict.insert from (Set.singleton to)
                                    |> DAG
                                )

            Nothing ->
                case edgesByNodes |> Dict.get from of
                    Just fromEdges ->
                        if from == to then
                            DAG edgesByNodes
                                |> Ok

                        else
                            edgesByNodes
                                |> Dict.insert from (Set.insert to fromEdges)
                                |> Dict.insert to Set.empty
                                |> DAG
                                |> Ok

                    Nothing ->
                        edgesByNodes
                            |> Dict.insert from (Set.singleton to)
                            |> Dict.insert to Set.empty
                            |> DAG
                            |> Ok


collectReachableNodesFrom : comparableNode -> DAG comparableNode -> Set comparableNode
collectReachableNodesFrom node (DAG edgesByNode) =
    Dict.get node edgesByNode
        |> Maybe.withDefault Set.empty
        |> (\firstReachableSet ->
                Set.foldl
                    (\n reachableSoFar ->
                        collectReachableNodesFrom n (DAG edgesByNode)
                            |> Set.union reachableSoFar
                    )
                    firstReachableSet
                    firstReachableSet
           )


{-| Inserts a Node into the dag and inserts outward edges from this
Node to a the Set of Nodes provided
-}
insertNode : comparableNode -> Set comparableNode -> DAG comparableNode -> Result (CycleDetected comparableNode) (DAG comparableNode)
insertNode fromNode toNodes (DAG edgesByNode) =
    let
        insertEdges : Set comparableNode -> DAG comparableNode -> Result (CycleDetected comparableNode) (DAG comparableNode)
        insertEdges nodes d =
            Set.toList nodes
                |> List.foldl
                    (\toNode dagResultSoFar ->
                        Result.andThen (insertEdge fromNode toNode) dagResultSoFar
                    )
                    (Ok d)

        makesCycle =
            toNodes
                |> Set.foldl
                    (\n foundCycle ->
                        if collectReachableNodesFrom n (DAG edgesByNode) |> Set.member fromNode then
                            True

                        else
                            foundCycle
                    )
                    False
    in
    if makesCycle then
        -- capture the nodes causing the cycle
        Err (CycleDetected fromNode fromNode)

    else if Dict.member fromNode edgesByNode then
        DAG edgesByNode
            |> insertEdges toNodes

    else
        edgesByNode
            |> Dict.insert fromNode Set.empty
            |> DAG
            |> insertEdges toNodes


{-| Removes and edge from one comparableNode

to another
If either nodes aren't found, then no change is made to the dag

-}
removeEdge : comparableNode -> comparableNode -> DAG comparableNode -> DAG comparableNode
removeEdge from to (DAG edgesByNode) =
    edgesByNode
        |> Dict.update from
            (Maybe.map
                (\set ->
                    set |> Set.remove to
                )
            )
        |> DAG


{-| Remove a comparableNode

and all incoming and outgoing edges to that comparableNode

.
The comparableNode

may be an orphanNode or may have edges.
If the comparableNode

doesn't exist within the DAG, then no changes to the DAG is made.

-}
removeNode : comparableNode -> DAG comparableNode -> DAG comparableNode
removeNode comparableNode (DAG edges) =
    case
        edges |> Dict.get comparableNode
    of
        Nothing ->
            DAG edges

        Just _ ->
            DAG edges
                |> removeIncomingEdges comparableNode
                |> deleteNode comparableNode


{-| Remove all incoming edges for this comparableNode
-}
removeIncomingEdges : comparableNode -> DAG comparableNode -> DAG comparableNode
removeIncomingEdges comparableNode dag =
    incomingEdges comparableNode dag
        |> Set.toList
        |> List.foldl
            (\from g ->
                removeEdge from
                    comparableNode
                    g
            )
            dag


{-| delete a comparableNode

and it's outgoingEdges from the dag.
If the comparableNode

is not in the dag, then no changes are made

-}
deleteNode : comparableNode -> DAG comparableNode -> DAG comparableNode
deleteNode comparableNode (DAG e) =
    e
        |> Dict.remove comparableNode
        |> DAG


{-| Get the outgoing edges of a given comparableNode

in the graph in the form of a set of nodes that the edges point to.

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
outgoingEdges fromNode (DAG edges) =
    edges
        |> Dict.get fromNode
        |> Maybe.withDefault Set.empty


{-| Get the incoming edges of a given comparableNode

in the graph in the form of a set of nodes that the edges point from.

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
incomingEdges toNode (DAG edges) =
    edges
        |> Dict.toList
        |> List.filterMap
            (\( fromNode, toNodes ) ->
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
        removeStartNodes : ( DAG comparableNode, List (List comparableNode) ) -> ( DAG comparableNode, List (List comparableNode) )
        removeStartNodes ( DAG d, topologicalOrder ) =
            let
                dagWithoutStartNodes : DAG comparableNode
                dagWithoutStartNodes =
                    d
                        |> Dict.filter
                            (\k _ ->
                                incomingEdges k (DAG d) |> Set.isEmpty |> not
                            )
                        |> DAG

                collectRootNodes : List comparableNode
                collectRootNodes =
                    d
                        |> Dict.toList
                        |> List.filterMap
                            (\( comparableNode, _ ) ->
                                if
                                    incomingEdges comparableNode
                                        (DAG d)
                                        |> Set.isEmpty
                                then
                                    Just comparableNode

                                else
                                    Nothing
                            )
            in
            if Dict.isEmpty d then
                ( DAG Dict.empty, topologicalOrder )

            else
                removeStartNodes ( dagWithoutStartNodes, collectRootNodes :: topologicalOrder )
    in
    removeStartNodes ( dag, [] )
        |> Tuple.second


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

    backwardTopologicalOrdering graph ==
        [ [ 5 ]
        , [ 3, 4 ]
        , [ 2 ]
        , [ 1 ]
        ]

-}
backwardTopologicalOrdering : DAG comparableNode -> List (List comparableNode)
backwardTopologicalOrdering dag =
    forwardTopologicalOrdering dag |> List.reverse


{-| returns the DAG as a List.
-}
toList : DAG comparableNode -> List ( comparableNode, Set comparableNode )
toList (DAG dict) =
    dict
        |> Dict.toList
