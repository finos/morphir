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
import Morphir.File.SourceCode as Doc exposing (Doc, concat, newLine, space)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type exposing (Type)
import Morphir.Metadata as Metadata exposing (Types)


type alias Options =
    { namespace : String }


mapDistribution : Options -> Distribution -> FileMap
mapDistribution opt distro =
    let
        metadata =
            Metadata.mapDistribution distro

        modules =
            Metadata.getModules metadata

        types =
            Metadata.getTypes metadata
    in
    [ toFile modules types ]
        |> Dict.fromList


toFile : List ModuleName -> Types ta -> ( ( List String, String ), String )
toFile modules types =
    let
        path =
            []

        file =
            "taxonomy.skos"

        content =
            prettyPrint modules types

        --PrettyPrinter.mapAttributes (PrettyPrinter.Options 2 100) attributes
    in
    ( ( path, file ), content )


prettyPrint : List ModuleName -> Types ta -> Doc
prettyPrint modules types =
    let
        lastPath : Path -> String
        lastPath path =
            path |> List.reverse |> List.head |> Maybe.map Name.toSnakeCase |> Maybe.withDefault "<root>"

        moduleSkos =
            modules
                |> List.map
                    (\moduleName ->
                        case List.reverse moduleName of
                            [] ->
                                Doc.empty

                            [ root ] ->
                                concat [ Name.toSnakeCase root, space, "-type->", space, "DomainElement", newLine ]

                            name :: root :: _ ->
                                concat
                                    [ concat [ Name.toSnakeCase name, space, "-skos:broader->", space, Name.toSnakeCase root, newLine ]
                                    , concat [ Name.toSnakeCase root, space, "-type->", space, "DomainElement", newLine ]
                                    ]
                    )

        typeSkos =
            types
                |> Dict.keys
                |> List.map (\fqn -> ( Name.toSnakeCase (FQName.getLocalName fqn), lastPath (FQName.getModulePath fqn) ))
                |> List.map
                    (\( name, domain ) ->
                        concat
                            [ concat [ name, space, "-type->", space, "DataElement", newLine ]
                            , concat [ name, space, "-skos:broader->", space, domain, newLine ]
                            ]
                    )
    in
    concat
        ([ concat [ "@prefix skos: <http://www.w3.org/2004/02/skos/core#> .", newLine ]
         , concat [ "@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .", newLine ]
         , newLine
         ]
            ++ moduleSkos
            ++ typeSkos
        )
