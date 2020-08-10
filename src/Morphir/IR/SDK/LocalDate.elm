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


module Morphir.IR.SDK.Date exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Common exposing (toFQName)
import Morphir.IR.Type exposing (Specification(..), Type(..))


moduleName : ModulePath
moduleName =
    Path.fromString "LocalDate"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "LocalDate", OpaqueTypeSpecification [] |> Documented "Type that represents a date concept." )
            ]
    , values =
        Dict.empty
    }


dateType : a -> Type a
dateType attributes =
    Reference attributes (toFQName moduleName "LocalDate") []
