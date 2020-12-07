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
import List.Extra exposing (unique, uniqueBy)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.File.SourceCode exposing (dotSep, newLine)
import Morphir.IR.AccessControlled as AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Distribution as Distribution exposing (Distribution, lookupTypeSpecification)
import Morphir.IR.FQName as FQName exposing (FQName(..))
import Morphir.IR.Module as Module exposing (Definition)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type exposing (Specification(..))
import Morphir.IR.Value as Value exposing (Value(..))
import Morphir.Graph.Tripler as Tripler exposing (Triple, Object(..), mapDistribution)

type alias Options =
    {}


mapDistribution : Options -> Distribution -> FileMap
mapDistribution opt distro =
    let 
        triples : List Tripler.Triple
        triples = Tripler.mapDistribution distro

        content = triples
            |> List.map (\triple -> 
                String.join ", " 
                    [ (subjectToString triple.subject)
                    , triple.verb
                    , (objectToString triple.object)
                    ]
            )
            |> String.join "\n"
    in
        Dict.fromList [((["dist"], "graph.txt"), content)]


subjectToString : FQName -> String
subjectToString fqn =
    String.join "."
        [ (Path.toString Name.toCamelCase "." (FQName.getModulePath fqn))
        , (Path.toString Name.toCamelCase "." (FQName.getPackagePath fqn))
        , (Name.toSnakeCase (FQName.getLocalName fqn))
        ]

objectToString : Object -> String
objectToString o =
    case o of 
        FQN (FQName modulePath packagePath name) ->
            String.join "."
                [ (Path.toString Name.toTitleCase "." modulePath)
                , (Path.toString Name.toSnakeCase "." packagePath)
                , (String.join "_" name)
                ]

        -- PathOf Path.Path ->
        Other s ->
            s
