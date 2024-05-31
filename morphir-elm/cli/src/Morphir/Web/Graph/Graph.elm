module Morphir.Web.Graph.Graph exposing (..)

import Dict exposing (Dict)
import Html exposing (..)
import Html.Attributes exposing (attribute)
import Json.Encode as Encode exposing (..)
import Morphir.IR.FQName as FQName
import Morphir.IR.Name as Name


type alias Node =
    { id : Int, label : String }


type alias Edge =
    { from : Int, to : Int }


type alias Graph =
    { nodes : List Node
    , edges : List Edge
    }


empty : Graph
empty =
    { nodes = [], edges = [] }


dagListAsGraph : List ( String, List String ) -> Graph
dagListAsGraph dagAsList =
    let
        indexByNode : Dict String Int
        indexByNode =
            dagAsList
                |> List.indexedMap
                    (\index item ->
                        ( Tuple.first item
                        , index
                        )
                    )
                |> Dict.fromList
    in
    Graph
        (indexByNode
            |> Dict.toList
            |> List.map
                (\( item, index ) ->
                    { label =
                        FQName.fromString item ":"
                            |> (\( _, _, name ) ->
                                    Name.toHumanWords name
                                        |> String.join " "
                               )
                    , id = index
                    }
                )
        )
        (dagAsList
            |> List.foldl
                (\( fromNode, edges ) edgeListSoFar ->
                    edges
                        |> List.map
                            (\toNode ->
                                { from = Dict.get fromNode indexByNode |> Maybe.withDefault -1
                                , to = Dict.get toNode indexByNode |> Maybe.withDefault -1
                                }
                            )
                        |> List.append edgeListSoFar
                )
                []
        )


visGraph : Graph -> Html msg
visGraph graphContent =
    node "vis-graph"
        [ attribute "graph" (encodeGraph graphContent |> Encode.encode 0)
        ]
        []


encodeNode : Node -> Encode.Value
encodeNode node =
    Encode.object <|
        [ ( "id", Encode.int node.id )
        , ( "label", Encode.string node.label )
        ]


encodeEdge : Edge -> Encode.Value
encodeEdge edge =
    Encode.object <|
        [ ( "to", Encode.int edge.to )
        , ( "from", Encode.int edge.from )
        ]


encodeGraph : Graph -> Encode.Value
encodeGraph g =
    Encode.object <|
        [ ( "nodes", Encode.list encodeNode g.nodes )
        , ( "edges", Encode.list encodeEdge g.edges )
        ]
