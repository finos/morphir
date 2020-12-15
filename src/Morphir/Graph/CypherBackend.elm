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
import List.Extra exposing (unique, uniqueBy)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.Graph.Tripler as Tripler exposing (NodeType(..), Object(..), Triple, Verb(..), mapDistribution, nodeTypeToString, verbToString)
import Morphir.IR.Distribution as Distribution exposing (Distribution, lookupTypeSpecification)
import Morphir.IR.FQName as FQName exposing (FQName(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path exposing (Path)
import Set


type alias Options =
    {}


mapDistribution : Options -> Distribution -> FileMap
mapDistribution opt distro =
    let
        triples =
            Tripler.mapDistribution distro
                |> List.concatMap
                    (\t ->
                        case t.object of
                            FQN fqn ->
                                [ Triple fqn Tripler.IsA (Node Tripler.Type) ]

                            _ ->
                                []
                    )
                |> List.append (Tripler.mapDistribution distro)
                |> uniqueBy tripleToString

        createTypes =
            triples
                |> List.filterMap
                    (\t ->
                        case t.object of
                            Node tipe ->
                                Just ("CREATE (n:" ++ nodeTypeToString tipe ++ " {id:'" ++ fqnToString t.subject ++ "', name:'" ++ Name.toSnakeCase (FQName.getLocalName t.subject) ++ "'});")

                            _ ->
                                Nothing
                    )

        isARelationships =
            triples
                |> List.filterMap
                    (\t ->
                        case ( t.verb, t.object ) of
                            ( IsA, FQN object ) ->
                                let
                                    matchs =
                                        "MATCH (s {id:'" ++ fqnToString t.subject ++ "'})"

                                    matcho =
                                        "MATCH (o:Type {id:'" ++ fqnToString object ++ "'})"

                                    create =
                                        "CREATE (s)-[:" ++ verbToString t.verb ++ "]->(o)"
                                in
                                Just (matchs ++ " " ++ matcho ++ " " ++ create ++ ";")

                            _ ->
                                Nothing
                    )

        aliasRelationships =
            triples
                |> List.filterMap
                    (\t ->
                        case ( t.verb, t.object ) of
                            ( Aliases, FQN object ) ->
                                let
                                    matchs =
                                        "MATCH (s {id:'" ++ fqnToString t.subject ++ "'})"

                                    matcho =
                                        "MATCH (o:Type {id:'" ++ fqnToString object ++ "'})"

                                    create =
                                        "CREATE (s)-[:" ++ verbToString t.verb ++ "]->(o)"
                                in
                                Just (matchs ++ " " ++ matcho ++ " " ++ create ++ ";")

                            _ ->
                                Nothing
                    )

        containsRelationships =
            triples
                |> List.filterMap
                    (\t ->
                        case ( t.verb, t.object ) of
                            ( Contains, FQN object ) ->
                                let
                                    matchs =
                                        "MATCH (s:Record {id:'" ++ fqnToString t.subject ++ "'})"

                                    matcho =
                                        "MATCH (o:Field {id:'" ++ fqnToString object ++ "'})"

                                    create =
                                        "CREATE (s)-[:" ++ verbToString t.verb ++ "]->(o)"
                                in
                                Just (matchs ++ " " ++ matcho ++ " " ++ create ++ ";")

                            _ ->
                                Nothing
                    )

        unionsRelationships =
            triples
                |> List.filterMap
                    (\t ->
                        case ( t.verb, t.object ) of
                            ( Unions, FQN object ) ->
                                let
                                    matchs =
                                        "MATCH (s:Type {id:'" ++ fqnToString t.subject ++ "'})"

                                    matcho =
                                        "MATCH (o:Type {id:'" ++ fqnToString object ++ "'})"

                                    create =
                                        "CREATE (s)-[:" ++ verbToString t.verb ++ "]->(o)"
                                in
                                Just (matchs ++ " " ++ matcho ++ " " ++ create ++ ";")

                            _ ->
                                Nothing
                    )
                |> unique

        usesRelationships =
            triples
                |> List.filterMap
                    (\t ->
                        case ( t.verb, t.object ) of
                            ( Uses, FQN object ) ->
                                let
                                    matchs =
                                        "MATCH (s:Function {id:'" ++ fqnToString t.subject ++ "'})"

                                    matcho =
                                        "MATCH (o {id:'" ++ fqnToString object ++ "'})"

                                    create =
                                        "CREATE (s)-[:" ++ verbToString t.verb ++ "]->(o)"
                                in
                                Just (matchs ++ " " ++ matcho ++ " " ++ create ++ ";")

                            _ ->
                                Nothing
                    )
                |> unique

        producesRelationships =
            triples
                |> List.filterMap
                    (\t ->
                        case ( t.verb, t.object ) of
                            ( Produces, FQN object ) ->
                                let
                                    matchs =
                                        "MATCH (s:Function {id:'" ++ fqnToString t.subject ++ "'})"

                                    matcho =
                                        "MATCH (o {id:'" ++ fqnToString object ++ "'})"

                                    create =
                                        "CREATE (s)-[:" ++ verbToString t.verb ++ "]->(o)"
                                in
                                Just (matchs ++ " " ++ matcho ++ " " ++ create ++ ";")

                            _ ->
                                Nothing
                    )
                |> unique

        content =
            [ createTypes
            , isARelationships
            , aliasRelationships
            , unionsRelationships
            , containsRelationships
            , usesRelationships
            , producesRelationships
            ]
                |> List.concat
                |> unique
                |> String.join "\n"
    in
    Dict.fromList [ ( ( [ "dist" ], "graph.cypher" ), content ) ]


tripleToString : Triple -> String
tripleToString triple =
    String.join ", "
        [ fqnToString triple.subject
        , verbToString triple.verb
        , objectToString triple.object
        ]


fqnToString : FQName -> String
fqnToString fqn =
    String.join "."
        [ Path.toString Name.toSnakeCase "." (FQName.getPackagePath fqn)
        , Path.toString Name.toSnakeCase "." (FQName.getModulePath fqn)
        , Name.toSnakeCase (FQName.getLocalName fqn)
        ]


objectToString : Object -> String
objectToString o =
    case o of
        FQN (FQName packagePath modulePath name) ->
            String.join "."
                [ Path.toString Name.toSnakeCase "." packagePath
                , Path.toString Name.toSnakeCase "." modulePath
                , String.join "_" name
                ]

        Node node ->
            nodeTypeToString node

        Other s ->
            s
