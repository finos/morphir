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

        createTypes =
            triples
                |> List.filterMap
                    (\t ->
                        case t.object of
                            FQN fqn ->
                                if List.member t.verb [ IsA, Aliases, Contains, Uses, Parameterizes, Unions ] then
                                    Just (Triple fqn Tripler.IsA (Node Tripler.Type))

                                else
                                    Nothing

                            _ ->
                                Nothing
                    )
                |> List.append triples
                |> uniqueBy tripleToString
                |> List.filterMap
                    (\t ->
                        case ( t.verb, t.object ) of
                            ( IsA, Node tipe ) ->
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
                                Just (toRelationship Nothing (Just "Type") t.subject t.verb t.object)

                            _ ->
                                Nothing
                    )

        aliasRelationships =
            triples
                |> List.filterMap
                    (\t ->
                        case ( t.verb, t.object ) of
                            ( Aliases, FQN object ) ->
                                Just (toRelationship Nothing (Just "Type") t.subject t.verb t.object)

                            _ ->
                                Nothing
                    )

        containsRelationships =
            triples
                |> List.filterMap
                    (\t ->
                        case ( t.verb, t.object ) of
                            ( Contains, FQN object ) ->
                                Just (toRelationship (Just "Record") (Just "Field") t.subject t.verb t.object)

                            _ ->
                                Nothing
                    )

        unionsRelationships =
            triples
                |> List.filterMap
                    (\t ->
                        case ( t.verb, t.object ) of
                            ( Unions, FQN object ) ->
                                Just (toRelationship (Just "Type") (Just "Type") t.subject t.verb t.object)

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
                                Just (toRelationship (Just "Function") Nothing t.subject t.verb t.object)

                            _ ->
                                Nothing
                    )
                |> unique

        callsRelationships =
            triples
                |> List.filterMap
                    (\t ->
                        case ( t.verb, t.object ) of
                            ( Calls, FQN objectFQN ) ->
                                if String.startsWith "morphir.SDK" (fqnToString objectFQN) then
                                    Nothing

                                else
                                    Just (toRelationship (Just "Function") (Just "Function") t.subject t.verb t.object)

                            _ ->
                                Nothing
                    )
                |> unique

        producesRelationships =
            triples
                |> List.filterMap
                    (\t ->
                        case ( t.verb, t.object ) of
                            ( Produces, object ) ->
                                Just (toRelationship (Just "Function") Nothing t.subject t.verb t.object)

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
            , callsRelationships
            , producesRelationships
            ]
                |> List.concat
                |> unique
                |> String.join "\n"
    in
    Dict.fromList [ ( ( [ "dist" ], "graph.cypher" ), content ) ]


toRelationship : Maybe String -> Maybe String -> FQName -> Verb -> Object -> String
toRelationship subjectNode objectNode subject verb object =
    let
        sn =
            subjectNode |> Maybe.map (\s -> ":" ++ s) |> Maybe.withDefault ""

        on =
            objectNode |> Maybe.map (\s -> ":" ++ s) |> Maybe.withDefault ""

        matchs =
            "MATCH (s" ++ sn ++ " {id:'" ++ fqnToString subject ++ "'})"

        matcho =
            "MATCH (o" ++ on ++ " {id:'" ++ objectToString object ++ "'})"

        create =
            "CREATE (s)-[:" ++ verbToString verb ++ "]->(o)"
    in
    matchs ++ " " ++ matcho ++ " " ++ create ++ ";"


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
        --FQN (FQName packagePath modulePath name) ->
        --    String.join "."
        --        [ Path.toString Name.toSnakeCase "." packagePath
        --        , Path.toString Name.toSnakeCase "." modulePath
        --        , String.join "_" name
        --        ]
        FQN fqn ->
            fqnToString fqn

        Node node ->
            nodeTypeToString node

        Other s ->
            s
