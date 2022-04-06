module Morphir.Dependency.DAG exposing
    ( DAG, CycleDetected(..)
    , empty, insertEdge
    , incomingEdges, outgoingEdges
    , forwardTopologicalOrdering, backwardTopologicalOrdering
    , toList, toListWithLevel
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

@docs toList, toListWithLevel

-}

import Dict exposing (Dict)
import Set exposing (Set)


{-| Type to store the DAG. Internally it keeps track of each node in a dictionary together with the outgoing edges and
the level they are at in the partial ordering.
-}
type DAG comparableNode
    = DAG (Dict comparableNode ( Set comparableNode, Level ))


type alias Level =
    Int


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
    let
        shiftTransitively : Int -> comparableNode -> DAG comparableNode -> DAG comparableNode
        shiftTransitively by n (DAG e) =
            case e |> Dict.get n of
                Just ( toNodes, level ) ->
                    toNodes
                        |> Set.remove n
                        |> Set.foldl (shiftTransitively by)
                            (DAG (e |> Dict.insert n ( toNodes, level + by )))

                Nothing ->
                    DAG e

        shiftAll : Int -> DAG comparableNode -> DAG comparableNode
        shiftAll by (DAG e) =
            e
                |> Dict.map
                    (\_ ( toNodes, level ) ->
                        ( toNodes, level + by )
                    )
                |> DAG
    in
    if from == to then
        case edgesByNodes |> Dict.get from of
            Just ( fromEdges, fromLevel ) ->
                edgesByNodes
                    |> Dict.insert from ( fromEdges |> Set.insert to, fromLevel )
                    |> DAG
                    |> Ok

            Nothing ->
                edgesByNodes
                    |> Dict.insert from ( Set.singleton to, 0 )
                    |> DAG
                    |> Ok

    else
        case edgesByNodes |> Dict.get to of
            Just ( toEdges, toLevel ) ->
                if toEdges |> Set.member from then
                    Err (CycleDetected from to)

                else
                    case edgesByNodes |> Dict.get from of
                        Just ( fromEdges, fromLevel ) ->
                            if fromEdges |> Set.member to then
                                -- duplicate edge, ignore
                                DAG edgesByNodes |> Ok

                            else if fromLevel < toLevel then
                                edgesByNodes
                                    |> Dict.insert from ( fromEdges |> Set.insert to, fromLevel )
                                    |> DAG
                                    |> Ok

                            else if fromLevel == toLevel then
                                edgesByNodes
                                    |> Dict.insert from ( fromEdges |> Set.insert to, fromLevel )
                                    |> DAG
                                    |> shiftTransitively 1 to
                                    |> Ok

                            else
                                Err (CycleDetected from to)

                        Nothing ->
                            Ok
                                (if toLevel == 0 then
                                    DAG edgesByNodes
                                        |> shiftAll 1
                                        |> (\(DAG e) ->
                                                DAG
                                                    (Dict.insert from ( Set.singleton to, 0 ) e)
                                           )

                                 else
                                    edgesByNodes
                                        |> Dict.insert from ( Set.singleton to, toLevel - 1 )
                                        |> DAG
                                )

            Nothing ->
                case edgesByNodes |> Dict.get from of
                    Just ( fromEdges, fromLevel ) ->
                        if from == to then
                            DAG edgesByNodes
                                |> Ok

                        else
                            edgesByNodes
                                |> Dict.insert from ( Set.insert to fromEdges, fromLevel )
                                |> Dict.insert to ( Set.empty, fromLevel + 1 )
                                |> DAG
                                |> Ok

                    Nothing ->
                        edgesByNodes
                            |> Dict.insert from ( Set.singleton to, 0 )
                            |> Dict.insert to ( Set.empty, 1 )
                            |> DAG
                            |> Ok


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

        -- get the highest level of incoming edge node
        -- used to assign a level to this node
        level : Level
        level =
            incomingEdges fromNode (DAG edgesByNode)
                |> Set.toList
                |> List.filterMap
                    (\incomingEdgeNode ->
                        case Dict.get incomingEdgeNode edgesByNode of
                            Just ( _, l ) ->
                                Just l

                            Nothing ->
                                Nothing
                    )
                |> List.maximum
                |> Maybe.withDefault -1
    in
    if Dict.member fromNode edgesByNode then
        DAG edgesByNode
            |> insertEdges toNodes

    else
        edgesByNode
            |> Dict.insert fromNode ( Set.empty, level + 1 )
            |> DAG
            |> insertEdges toNodes


{-| Removes and edge from one node to another
If either nodes aren't found, then no change is made to the dag
-}
removeEdge : comparableNode -> comparableNode -> DAG comparableNode -> DAG comparableNode
removeEdge from to (DAG edgesByNode) =
    edgesByNode
        |> Dict.update from
            (Maybe.map
                (\( set, level ) ->
                    ( set |> Set.remove to, level )
                )
            )
        |> DAG
        |> rebuild


{-| Remove a node and all incoming and outgoing edges to that node.
The node may be an orphanNode or may have edges.
If the node doesn't exist within the DAG, then no changes to the DAG is made.
-}
removeNode : comparableNode -> DAG comparableNode -> DAG comparableNode
removeNode node (DAG edges) =
    case edges |> Dict.get node of
        Nothing ->
            DAG edges

        Just _ ->
            DAG edges
                |> removeIncomingEdges node
                |> deleteNode node
                |> rebuild


{-| Remove all incoming edges for this node
-}
removeIncomingEdges : comparableNode -> DAG comparableNode -> DAG comparableNode
removeIncomingEdges node dag =
    incomingEdges node dag
        |> Set.toList
        |> List.foldl
            (\from g ->
                removeEdge from node g
            )
            dag


{-| builds a new dag from an existing one.
useful for re-leveling a dag.
The assumption is that the DAG is in a valid state and has no cycles.
-}
rebuild : DAG comparableNode -> DAG comparableNode
rebuild (DAG d) =
    Dict.toList d
        |> List.foldl
            (\( fromNode, ( toNodes, _ ) ) newDagSoFar ->
                insertNode fromNode toNodes newDagSoFar
                    |> Result.withDefault newDagSoFar
            )
            empty


{-| delete a node and it's outgoingEdges from the dag.
If the node is not in the dag, then no changes are made
-}
deleteNode : comparableNode -> DAG comparableNode -> DAG comparableNode
deleteNode node (DAG e) =
    e
        |> Dict.remove node
        |> DAG


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
outgoingEdges fromNode (DAG edges) =
    edges
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
incomingEdges toNode (DAG edges) =
    edges
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
forwardTopologicalOrdering (DAG edgesByNode) =
    let
        dagList : List ( comparableNode, Int )
        dagList =
            edgesByNode
                |> Dict.toList
                |> List.map
                    (\( fromNode, ( _, fromNodeLevel ) ) ->
                        ( fromNode, fromNodeLevel )
                    )

        maxLevel : Int
        maxLevel =
            dagList
                |> List.map (\( _, level ) -> level)
                |> List.maximum
                |> Maybe.withDefault 0
    in
    List.range 0 maxLevel
        |> List.map
            (\level ->
                dagList
                    |> List.filterMap
                        (\( fromNode, fromNodeLevel ) ->
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
        |> Dict.map (\_ ( a, _ ) -> a)
        |> Dict.toList


{-| returns the DAG as a List with the level information
-}
toListWithLevel : DAG comparableNode -> List ( comparableNode, ( Set comparableNode, Int ) )
toListWithLevel (DAG dict) =
    dict
        |> Dict.toList
