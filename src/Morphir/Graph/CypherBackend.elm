{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}


module Morphir.Graph.CypherBackend exposing (..)

import Dict
import List.Extra exposing (unique)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.Graph.Grapher as Grapher exposing (Edge, GraphEntry(..), Node(..), nodeType, verbToString)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path exposing (Path)


type alias Options =
    {}


mapDistribution : Options -> Distribution -> FileMap
mapDistribution opt distro =
    let
        graphEntries =
            Grapher.mapDistribution distro

        -- Splitting the nodes from the edges because we want to create them first
        nodes =
            graphEntries
                |> List.filterMap
                    (\entry ->
                        case entry of
                            NodeEntry node ->
                                Just (nodeToCreate node)

                            _ ->
                                Nothing
                    )

        edges =
            graphEntries
                |> List.filterMap
                    (\entry ->
                        case entry of
                            EdgeEntry edge ->
                                Just (toRelationship edge)

                            _ ->
                                Nothing
                    )

        content =
            [ nodes
            , edges
            ]
                |> List.concat
                |> unique
                |> String.join "\n"
    in
    Dict.fromList [ ( ( [ "dist" ], "graph.cypher" ), content ) ]


toRelationship : Edge -> String
toRelationship edge =
    let
        ( subjectType, subjectId, _ ) =
            splitNode edge.subject

        ( objectType, objectId, _ ) =
            splitNode edge.object

        matchs =
            "MATCH (s:" ++ subjectType ++ " {id:'" ++ subjectId ++ "'})"

        matcho =
            "MATCH (o:" ++ objectType ++ " {id:'" ++ objectId ++ "'})"

        create =
            "CREATE (s)-[:" ++ verbToString edge.verb ++ "]->(o)"
    in
    matchs ++ " " ++ matcho ++ " " ++ create ++ ";"


splitNode : Grapher.Node -> ( String, String, String )
splitNode node =
    let
        humanize : Name -> String
        humanize name =
            Name.toHumanWords name
                |> String.join " "
    in
    case node of
        Record fqn ->
            ( nodeType node, fqnToString fqn, humanize (FQName.getLocalName fqn) )

        Field fqn name ->
            ( nodeType node, fqnToString fqn ++ "#" ++ Name.toSnakeCase name, humanize name )

        Type fqn ->
            ( nodeType node, fqnToString fqn, humanize (FQName.getLocalName fqn) )

        Function fqn ->
            ( nodeType node, fqnToString fqn, humanize (FQName.getLocalName fqn) )

        Enum fqn ->
            ( nodeType node, fqnToString fqn, humanize (FQName.getLocalName fqn) )

        UnitOfMeasure fqn ->
            ( nodeType node, fqnToString fqn, humanize (FQName.getLocalName fqn) )

        Unknown s ->
            ( "Unknown", "unknown", s )


nodeToCreate : Grapher.Node -> String
nodeToCreate node =
    let
        ( tipe, id, name ) =
            splitNode node
    in
    "CREATE (n:" ++ tipe ++ " {id:'" ++ id ++ "', name:'" ++ name ++ "'});"


fqnToString : FQName -> String
fqnToString fqn =
    String.join "."
        [ Path.toString Name.toSnakeCase "." (FQName.getPackagePath fqn)
        , Path.toString Name.toSnakeCase "." (FQName.getModulePath fqn)
        , Name.toSnakeCase (FQName.getLocalName fqn)
        ]
