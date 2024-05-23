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


module Morphir.Graph.SemanticBackend exposing (..)

import Dict
import List.Extra as List
import Morphir.File.FileMap exposing (FileMap)
import Morphir.File.SourceCode as Doc exposing (Doc, concat, indentLines, newLine, space)
import Morphir.Graph.CypherBackend exposing (Options)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type exposing (Type)
import Morphir.Metadata as Metadata exposing (Types)
import Set


mapDistribution : Options -> Distribution -> FileMap
mapDistribution options distro =
    let
        metadata =
            Metadata.mapDistribution distro

        modules =
            Metadata.getModules metadata

        types =
            Metadata.getTypes metadata

        package =
            Distribution.lookupPackageName distro |> toFQName
    in
    [ toFile package modules types ]
        |> Dict.fromList


toFile : FQName -> List ModuleName -> Types ta -> ( ( List String, String ), String )
toFile package modules types =
    let
        path =
            []

        file =
            "taxonomy.ttl"

        content =
            prettyPrint package modules types

        --PrettyPrinter.mapAttributes (PrettyPrinter.Options 2 100) attributes
    in
    ( ( path, file ), content )


prettyPrint : FQName -> List ModuleName -> Types ta -> Doc
prettyPrint package modules types =
    -- TODO clean up the redundancy with proper grammar
    let
        namespacePrefix =
            package |> FQName.getLocalName |> Name.toSnakeCase

        namespaceIRI =
            Debug.log ".." package |> fqnToIRI

        reducePath modulePath =
            case modulePath of
                [] ->
                    []

                [ name ] ->
                    [ FQName.fQName [] [] name ]

                _ ->
                    let
                        fqn =
                            toFQName modulePath
                    in
                    fqn :: reducePath (FQName.getModulePath fqn)

        moduleFqns =
            modules
                |> List.concatMap reducePath
                |> Set.fromList

        toSkos : String -> FQName -> Doc
        toSkos skosType fqn =
            case fqn of
                ( _, [], [] ) ->
                    Doc.empty

                ( _, [], name ) ->
                    concat
                        [ concat [ namespacePrefix, ":", Name.toSnakeCase name, space, "rdf:type", space, skosType, space, ";", newLine ]
                        , indentLines 2
                            [ concat [ "skos:prefLabel", space, "\"", Name.toHumanWords name |> String.join " ", "\"", space, "." ]
                            ]
                        , newLine
                        , newLine
                        ]

                ( _, domain, name ) ->
                    concat
                        [ concat [ namespacePrefix, ":", Name.toSnakeCase name, space, "rdf:type", space, skosType, space, ";", newLine ]
                        , indentLines 2
                            [ concat [ "skos:prefLabel", space, "\"", Name.toHumanWords name |> String.join " ", "\"", space, ";" ]
                            , concat [ "skos:broader", space, namespacePrefix, ":", Name.toSnakeCase (FQName.getLocalName (toFQName domain)), space, "." ]
                            ]
                        , newLine
                        , newLine
                        ]

        dataDomainConcept =
            namespacePrefix ++ ":" ++ "DataDomain"

        dataElementConcept =
            namespacePrefix ++ ":" ++ "DataElement"

        moduleSkos =
            moduleFqns
                |> Set.toList
                |> List.sortBy (\x -> String.toLower (FQName.toString x))
                |> List.map (toSkos dataDomainConcept)

        typeSkos =
            types
                |> Dict.keys
                |> List.map (toSkos dataElementConcept)
    in
    concat
        ([ concat [ "@prefix", space, namespacePrefix, ":", space, "<", namespaceIRI, ">", space, ".", newLine ]
         , concat [ "@prefix skos: <http://www.w3.org/2004/02/skos/core#> .", newLine ]
         , concat [ "@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .", newLine ]
         , newLine
         , concat [ dataDomainConcept, space, "rdf:type", space, "skos:Concept", space, ";", newLine ]
         , indentLines 2
            [ concat [ "skos:prefLabel", space, "\"Data Domain\"", space, ";" ]
            , concat [ "skos:broader", space, "skos:Concept", space, "." ]
            ]
         , newLine
         , newLine
         , concat [ dataElementConcept, space, "rdf:type", space, "skos:Concept", space, ";", newLine ]
         , indentLines 2
            [ concat [ "skos:prefLabel", space, "\"Data Element\"", space, ";" ]
            , concat [ "skos:broader", space, "skos:Concept", space, "." ]
            ]
         , newLine
         , newLine
         ]
            ++ moduleSkos
            ++ typeSkos
        )


toFQName : Path -> FQName
toFQName path =
    let
        ( localName, newModulePath ) =
            List.unconsLast path
                |> Maybe.withDefault ( [], [] )
    in
    FQName.fQName [] newModulePath localName


fqnToIRI : FQName -> String
fqnToIRI fqn =
    String.join "/"
        [ moduleToIRI fqn
        , Name.toSnakeCase (FQName.getLocalName fqn)
        ]


moduleToIRI : FQName -> String
moduleToIRI fqn =
    [ FQName.getPackagePath fqn
    , FQName.getModulePath fqn
    ]
        |> List.concat
        |> List.map Name.toSnakeCase
        |> (::) "http:/"
        |> String.join "/"
