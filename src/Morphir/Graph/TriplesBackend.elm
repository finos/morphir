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


module Morphir.Graph.TriplesBackend exposing (..)

import Dict
import List.Extra exposing (unique, uniqueBy)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.Distribution as Distribution exposing (Distribution, lookupTypeSpecification)
import Morphir.IR.FQName as FQName exposing (FQName(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path exposing (Path)
import Set


type alias Options =
    {}



-- TODO: implement RDF


mapDistribution : Options -> Distribution -> FileMap
mapDistribution opt distro =
    Dict.empty
