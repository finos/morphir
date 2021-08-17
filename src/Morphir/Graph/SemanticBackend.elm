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
import Morphir.File.FileMap exposing (FileMap)
import Morphir.File.SourceCode as Doc exposing (Doc, concat, indentLines, newLine, space)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type exposing (Type)
import Morphir.Metadata as Metadata exposing (Types)


type alias Options =
    { namespace : ( String, String )

    --, includes : List ( String, String )
    }


mapDistribution : Options -> Distribution -> FileMap
mapDistribution options distro =
    let
        metadata =
            Metadata.mapDistribution distro

        modules =
            Metadata.getModules metadata

        types =
            Metadata.getTypes metadata
    in
    [ toFile options modules types ]
        |> Dict.fromList


toFile : Options -> List ModuleName -> Types ta -> ( ( List String, String ), String )
toFile options modules types =
    let
        path =
            []

        file =
            "taxonomy.skos"

        content =
            prettyPrint options modules types

        --PrettyPrinter.mapAttributes (PrettyPrinter.Options 2 100) attributes
    in
    ( ( path, file ), content )


prettyPrint : Options -> List ModuleName -> Types ta -> Doc
prettyPrint options modules types =
    -- TODO clean up the redundancy with proper grammar
    let
        ( namespacePrefix, namespaceIRI ) =
            options.namespace

        --lastPath : Path -> String
        --lastPath path =
        --    path |> List.reverse |> List.head |> Maybe.map Name.toSnakeCase |> Maybe.withDefault "<root>"
        moduleSkos =
            modules
                |> List.map
                    (\moduleName ->
                        case List.reverse moduleName of
                            [] ->
                                Doc.empty

                            [ name ] ->
                                concat
                                    [ concat [ namespacePrefix, ":", Name.toSnakeCase name, space, "rdf:type", space, "sko:Concept", space, ";", newLine ]
                                    , indentLines 2
                                        [ concat [ "skos:prefLabel", space, "\"", Name.toHumanWords name |> String.join " ", "\"", space, ".", newLine ]
                                        ]
                                    , newLine
                                    ]

                            name :: root :: _ ->
                                concat
                                    [ concat [ namespacePrefix, ":", Name.toSnakeCase name, space, "rdf:type", space, "sko:Concept", space, ";", newLine ]
                                    , indentLines 2
                                        [ concat [ "skos:prefLabel", space, "\"", Name.toHumanWords name |> String.join " ", "\"", space, ".", newLine ]
                                        , concat [ "skos:broader", space, namespacePrefix, ":", namespacePrefix, ":", Name.toSnakeCase name, space, ".", newLine ]
                                        ]
                                    ]
                    )

        typeSkos =
            types
                |> Dict.keys
                |> List.map (\fqn -> ( FQName.getLocalName fqn, FQName.getModulePath fqn |> List.reverse |> List.head |> Maybe.withDefault [] ))
                |> List.map
                    (\( name, domain ) ->
                        concat
                            [ concat [ namespacePrefix, ":", Name.toSnakeCase name, space, "rdf:type", space, namespacePrefix, ":", "DataElement", space, ";", newLine ]
                            , indentLines 2
                                [ concat [ "skos:prefLabel", space, "\"", Name.toHumanWords name |> String.join " ", "\"", space, ";", newLine ]
                                , concat [ "skos:broader", space, namespacePrefix, ":", namespacePrefix, ":", Name.toSnakeCase domain, space, ".", newLine ]
                                ]
                            ]
                    )
    in
    concat
        ([ concat [ "@prefix", space, namespacePrefix, ":", space, "<", namespaceIRI, ">", space, ".", newLine ]
         , concat [ "@prefix skos: <http://www.w3.org/2004/02/skos/core#> .", newLine ]
         , concat [ "@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .", newLine ]
         , newLine
         ]
            ++ moduleSkos
            ++ typeSkos
        )


fqnToURI : FQName -> String
fqnToURI fqn =
    String.join "/"
        [ moduleToURI fqn
        , Name.toSnakeCase (FQName.getLocalName fqn)
        ]


moduleToURI : FQName -> String
moduleToURI fqn =
    String.join "/"
        [ "http:/"
        , Path.toString Name.toSnakeCase "/" (FQName.getPackagePath fqn)
        , Path.toString Name.toSnakeCase "/" (FQName.getModulePath fqn)
        ]
