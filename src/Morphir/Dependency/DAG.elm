module Morphir.Dependency.DAG exposing
    ( DAG, CycleDetected(..)
    , empty, insertEdge
    , incomingEdges, outgoingEdges, collectForwardReachableNodes
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

@docs incomingEdges, outgoingEdges, collectForwardReachableNodes


# Ordering

@docs forwardTopologicalOrdering, backwardTopologicalOrdering


# Transforming

@docs toList

-}

import Dict exposing (Dict)
import Set exposing (Set)


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
        -- recursive, simply insert the node into the edges
        Dict.get from edgesByNodes
            |> Maybe.withDefault Set.empty
            |> (\edges -> Dict.insert from (Set.insert to edges) edgesByNodes)
            |> DAG
            |> Ok

    else if DAG edgesByNodes |> collectForwardReachableNodes to |> Set.member from then
        -- fromNode shouldn't be reachable from toNode
        Err (CycleDetected from to)

    else if edgesByNodes |> Dict.get from |> Maybe.withDefault Set.empty |> Set.member to then
        -- duplicate edge, ignore
        DAG edgesByNodes |> Ok

    else if Dict.member to edgesByNodes then
        -- do not add the toNode to the dict if it has already been inserted
        edgesByNodes
            |> Dict.get from
            |> Maybe.withDefault Set.empty
            |> (\fromEdges -> Dict.insert from (Set.insert to fromEdges) edgesByNodes)
            |> DAG
            |> Ok

    else
        -- add the edge, and insert toNode with empty edges to the dict
        edgesByNodes
            |> Dict.get from
            |> Maybe.withDefault Set.empty
            |> (\fromEdges -> Dict.insert from (Set.insert to fromEdges) edgesByNodes)
            |> Dict.insert to Set.empty
            |> DAG
            |> Ok


{-| Collect all the nodes that are reachable from a specific node.
If there is a _forward_ path from a to f through b, c, d and e, then they are all collected.
If a node is recursive (i.e self referencing), it is also included in the result as a reachableNode.

    example:
        dag = DAG
            (Dict.fromList
                [ ( "a", Set.fromList [ "b", "c", ] )
                , ( "c", Set.fromList [ "i" ] )
                , ( "b", Set.fromList [ "b", "d", "e" ] )
                , ( "e", Set.fromList [ "f" ] )
                , ( "f", Set.fromList [ "g", "c" ] )
                ]
            )

        collectForwardReachableNodes "a" dag == Set.fromList [ "b", "c", "d", "e", "i", "f", "g", "c" ]
        collectForwardReachableNodes "b" dag == Set.fromList [ "b", "d", "e", "f", "g", "c" ]

-}
collectForwardReachableNodes : comparableNode -> DAG comparableNode -> Set comparableNode
collectForwardReachableNodes firstNode (DAG initialEdgesByNode) =
    let
        firstReachableNodes : Set comparableNode
        firstReachableNodes =
            initialEdgesByNode
                |> Dict.get firstNode
                |> Maybe.withDefault Set.empty

        collect : Set comparableNode -> Dict comparableNode (Set comparableNode) -> Set comparableNode
        collect reachableSoFar currentEdgesByNode =
            let
                ( reachableEdges, unreachableEdges ) =
                    currentEdgesByNode
                        |> Dict.partition (\fromNode _ -> Set.member fromNode reachableSoFar)

                nextReachableNodes : Set comparableNode
                nextReachableNodes =
                    Set.diff
                        (reachableEdges
                            |> Dict.values
                            |> List.foldl Set.union Set.empty
                        )
                        reachableSoFar
            in
            if Set.isEmpty nextReachableNodes then
                reachableSoFar

            else
                collect (Set.union reachableSoFar nextReachableNodes) unreachableEdges
    in
    collect firstReachableNodes initialEdgesByNode


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
    in
    if Dict.member fromNode edgesByNode then
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
    backwardTopologicalOrdering dag |> List.reverse


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
backwardTopologicalOrdering (DAG dag) =
    let
        removeStartNodes : ( DAG comparableNode, List (List comparableNode) ) -> ( DAG comparableNode, List (List comparableNode) )
        removeStartNodes ( DAG d, topologicalOrder ) =
            let
                dagWithoutStartNodes : DAG comparableNode
                dagWithoutStartNodes =
                    d
                        |> Dict.filter
                            (\node _ ->
                                incomingEdges node (DAG d)
                                    |> Set.isEmpty
                                    |> not
                            )
                        |> DAG

                collectStartNodes : List comparableNode
                collectStartNodes =
                    d
                        |> Dict.toList
                        |> List.filterMap
                            (\( comparableNode, _ ) ->
                                if incomingEdges comparableNode (DAG d) |> Set.isEmpty then
                                    Just comparableNode

                                else
                                    Nothing
                            )
            in
            if Dict.isEmpty d then
                ( DAG Dict.empty, topologicalOrder )

            else
                removeStartNodes ( dagWithoutStartNodes, collectStartNodes :: topologicalOrder )
    in
    -- remove node self-referencing
    removeStartNodes ( dag |> Dict.map Set.remove |> DAG, [] )
        |> Tuple.second


{-| returns the DAG as a List.
-}
toList : DAG comparableNode -> List ( comparableNode, Set comparableNode )
toList (DAG dict) =
    dict
        |> Dict.toList
