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


module Morphir.Graph.Backend exposing (..)

import Dict
import Set
import List.Extra exposing (unique, uniqueBy)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.Distribution as Distribution exposing (Distribution, lookupTypeSpecification)
import Morphir.IR.FQName as FQName exposing (FQName(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.Graph.Tripler as Tripler exposing (Triple, Object(..), NodeType(..), Verb(..), mapDistribution)

type alias Options =
    {}


mapDistribution : Options -> Distribution -> FileMap
mapDistribution opt distro =
    let 
        triples : List Tripler.Triple
        triples = Tripler.mapDistribution distro
        content =
            triples
                |> List.concatMap
                    (\t ->
                        if t.verb == Tripler.IsA then
                            case t.object of
                                FQN fqn ->
                                    [Triple fqn Tripler.IsA (Node Tripler.Type)]
                                _ ->
                                    []
                        else
                            []
                    )
                |> List.append triples
                |> List.map tripleToString
                |> List.sort
                |> unique
                |> String.join "\n"
    in
        Dict.fromList [((["dist"], "graph.txt"), content)]


tripleToString : Triple -> String
tripleToString triple =
    String.join ", "
        [ (subjectToString triple.subject)
        , (verbToString triple.verb)
        , (objectToString triple.object)
        ]


subjectToString : FQName -> String
subjectToString fqn =
    String.join "."
        [ (Path.toString Name.toSnakeCase "." (FQName.getPackagePath fqn))
        , (Path.toString Name.toSnakeCase "." (FQName.getModulePath fqn))
        , (Name.toSnakeCase (FQName.getLocalName fqn))
        ]

objectToString : Object -> String
objectToString o =
    case o of 
        FQN (FQName packagePath modulePath name) ->
            String.join "."
                [ (Path.toString Name.toSnakeCase "." packagePath)
                , (Path.toString Name.toSnakeCase "." modulePath)
                , (String.join "_" name)
                ]
        Node node ->
            case node of
                Tripler.Record -> "Record"
                Tripler.Field -> "Field"
                Tripler.Type -> "Type"
                Tripler.Function -> "Function"

        -- PathOf Path.Path ->
        Other s ->
            s


verbToString : Tripler.Verb -> String
verbToString verb =
    case verb of
        Tripler.IsA -> "isA"
        Tripler.Contains -> "contains"