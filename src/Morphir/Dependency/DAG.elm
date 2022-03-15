module Morphir.Dependency.DAG exposing
    ( DAG, CycleDetected
    , empty, insertEdge
    , incomingEdges, outgoingEdges
    , forwardTopologicalOrdering, backwardTopologicalOrdering
    , insertNode, removeEdge, removeNode, removeNodeAndSubtrees
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
type DAG comparableNode
    = DAG (Dict comparableNode ( Set comparableNode, Int )) (Set comparableNode)



-- MAYBE NEW STRUCTURE


type DAG2 comparableNode
    = DAG2 (Set ( Node comparableNode, Level ))


type Node comparableNode
    = InnerNode (Set comparableNode)
    | LeafNode


type alias Level =
    Int


type DAG3 comparableNode
    = DAG3 (Set ( Node comparableNode, Level ))



--
--


{-| The error that's reported when a cycle is detected in the graph.
-}
type CycleDetected
    = CycleDetected


{-| Creates an empty DAG with no nodes or edges.
-}
empty : DAG comparableNode
empty =
    DAG Dict.empty Set.empty


{-| Inserts an edge defined by the from and to nodes. Returns an error if a cycle would be formed by the edge.
This design makes sure that a DAG cannot possibly have cycles in it since there is no way to create such a DAG.
-}
insertEdge : comparableNode -> comparableNode -> DAG comparableNode -> Result CycleDetected (DAG comparableNode)
insertEdge from to (DAG edges orphanNodes) =
    let
        shiftTransitively : Int -> comparableNode -> DAG comparableNode -> DAG comparableNode
        shiftTransitively by n (DAG e on) =
            case e |> Dict.get n of
                Just ( toNodes, level ) ->
                    toNodes
                        |> Set.foldl (shiftTransitively by)
                            (DAG (e |> Dict.insert n ( toNodes, level + by )) on)

                Nothing ->
                    DAG e on

        shiftAll : Int -> DAG comparableNode -> DAG comparableNode
        shiftAll by (DAG e ons) =
            DAG
                (e
                    |> Dict.map (\_ ( toNodes, level ) -> ( toNodes, level + by ))
                )
                ons

        removeFromOrphan : comparableNode -> Set comparableNode -> Set comparableNode
        removeFromOrphan node ons =
            if ons |> Set.member node then
                ons |> Set.remove node

            else
                ons
    in
    case edges |> Dict.get to of
        Just ( toEdges, toLevel ) ->
            if toEdges |> Set.member from then
                Err CycleDetected

            else
                case edges |> Dict.get from of
                    Just ( fromEdges, fromLevel ) ->
                        if fromEdges |> Set.member to then
                            -- duplicate edge, ignore
                            Ok (DAG edges orphanNodes)

                        else if fromLevel < toLevel then
                            DAG
                                (edges |> Dict.insert from ( fromEdges |> Set.insert to, fromLevel ))
                                (removeFromOrphan from orphanNodes)
                                |> Ok

                        else if fromLevel == toLevel then
                            DAG
                                (edges |> Dict.insert from ( fromEdges |> Set.insert to, fromLevel ))
                                (removeFromOrphan from orphanNodes)
                                |> shiftTransitively 1 to
                                |> Ok

                        else
                            Err CycleDetected

                    Nothing ->
                        Ok
                            (if toLevel == 0 then
                                DAG edges orphanNodes
                                    |> shiftAll 1
                                    |> (\(DAG e on) ->
                                            DAG
                                                (Dict.insert from ( Set.singleton to, 0 ) e)
                                                (removeFromOrphan from on)
                                       )

                             else
                                DAG
                                    (edges
                                        |> Dict.insert from ( Set.singleton to, toLevel - 1 )
                                    )
                                    (removeFromOrphan from orphanNodes)
                            )

        Nothing ->
            case edges |> Dict.get from of
                Just ( fromEdges, fromLevel ) ->
                    DAG
                        (edges
                            |> Dict.insert from ( fromEdges |> Set.insert to, fromLevel )
                            |> Dict.insert to ( Set.empty, fromLevel + 1 )
                        )
                        (removeFromOrphan from orphanNodes)
                        |> Ok

                Nothing ->
                    DAG
                        (edges
                            |> Dict.insert from ( Set.singleton to, 0 )
                            |> Dict.insert to ( Set.empty, 1 )
                        )
                        (removeFromOrphan from orphanNodes)
                        |> Ok


{-| Insert node without edges. Inserts node into orphan nodes set if the from node is does not exist in the edges.
This design makes room for nodes that are stand alone and do not have any connection to other nodes.
-}
insertNode : comparableNode -> Set comparableNode -> DAG comparableNode -> Result CycleDetected (DAG comparableNode)
insertNode fromNode toNodes (DAG edges orphanNodes) =
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
        insertIntoOrphanNodes (DAG e on) =
            DAG e (Set.insert fromNode on)
    in
    case edges |> Dict.get fromNode of
        Just _ ->
            DAG edges orphanNodes
                |> insertEdges

        Nothing ->
            DAG edges orphanNodes
                |> insertIntoOrphanNodes
                |> insertEdges


{-| Removes and edge from one node to another
If either nodes aren't found, then no change is made to the dag
-}
removeEdge : comparableNode -> comparableNode -> DAG comparableNode -> DAG comparableNode
removeEdge from to graph =
    graph
        |> (\(DAG edges orphanNodes) ->
                DAG
                    (edges
                        |> Dict.update from
                            (Maybe.map
                                (\( set, level ) ->
                                    ( set |> Set.remove to, level )
                                )
                            )
                    )
                    orphanNodes
           )


{-| Remove a node and all incoming and outgoing edges to that node.
The node may be an orphanNode or may have edges.
If the node doesn't exist within the DAG, then no changes to the DAG is made.
-}
removeNode : comparableNode -> DAG comparableNode -> DAG comparableNode
removeNode node (DAG edges orphanNodes) =
    case orphanNodes |> Set.member node of
        True ->
            orphanNodes
                |> Set.remove node
                |> DAG edges

        False ->
            case edges |> Dict.get node of
                Nothing ->
                    -- TODO: node might be a leaf, so we search for it
                    DAG edges orphanNodes

                Just _ ->
                    DAG edges orphanNodes
                        |> removeIncomingEdges node
                        |> deleteNode node


{-| Removes a node from the DAG. The node may be an orphanNode or may have edges.
If a node with edges is removed, then all subtrees are also removed if they have no other incoming edge.
if the node does not exist within the DAG, then no changes to the DAG is made.
-}
removeNodeAndSubtrees : comparableNode -> DAG comparableNode -> DAG comparableNode
removeNodeAndSubtrees node (DAG edges orphanNodes) =
    case orphanNodes |> Set.member node of
        True ->
            orphanNodes
                |> Set.remove node
                |> DAG edges

        False ->
            case edges |> Dict.get node of
                Nothing ->
                    -- TODO: node might be a leaf, so we search for it
                    DAG edges orphanNodes

                Just _ ->
                    let
                        --find nodes having incoming edges from only this node
                        removeOutgoingEdges dag =
                            outgoingEdges node dag
                                |> Set.toList
                                |> List.filter
                                    (\outgoingNode ->
                                        dag
                                            |> incomingEdges outgoingNode
                                            |> (\incomingNodes -> incomingNodes == Set.fromList [ node ])
                                    )
                                --recursively remove outgoing edges
                                |> List.foldl removeNodeAndSubtrees dag
                    in
                    DAG edges orphanNodes
                        |> removeOutgoingEdges
                        |> removeIncomingEdges node


{-| Remove all outgoing edges for this node
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


{-| delete a node from the dag
If the node is not in the dag, then no changes are made
-}
deleteNode : comparableNode -> DAG comparableNode -> DAG comparableNode
deleteNode node (DAG e ons) =
    e
        |> Dict.remove node
        |> (\modifiedEdges -> DAG modifiedEdges ons)


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
outgoingEdges fromNode (DAG edges _) =
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
incomingEdges toNode (DAG edges _) =
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
forwardTopologicalOrdering (DAG edges orphanNodes) =
    let
        edgeList : List ( comparableNode, Int )
        edgeList =
            edges
                |> Dict.toList
                |> List.map
                    (\( fromNode, ( _, fromNodeLevel ) ) ->
                        ( fromNode, fromNodeLevel )
                    )

        orphanNodeList : List ( comparableNode, Int )
        orphanNodeList =
            orphanNodes
                |> Set.toList
                |> List.map (\n -> ( n, 0 ))

        dagList : List ( comparableNode, Int )
        dagList =
            List.concat [ edgeList, orphanNodeList ]

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
