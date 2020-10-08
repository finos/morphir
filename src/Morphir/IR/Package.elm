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


module Morphir.IR.Package exposing
    ( Specification
    , Definition, emptyDefinition
    , lookupModuleSpecification, lookupTypeSpecification, lookupValueSpecification
    , PackageName, definitionToSpecification, eraseDefinitionAttributes, eraseSpecificationAttributes
    )

{-| Tools to work with packages.

@docs Specification

@docs Definition, emptyDefinition


# Lookups

@docs lookupModuleSpecification, lookupTypeSpecification, lookupValueSpecification


# Other utilities

@docs PackageName, definitionToSpecification, eraseDefinitionAttributes, eraseSpecificationAttributes

-}

import Dict exposing (Dict)
import Morphir.IR.AccessControlled exposing (AccessControlled, withPublicAccess)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Path exposing (Path)
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value


{-| -}
type alias PackageName =
    Path


{-| Type that represents a package specification.
-}
type alias Specification ta =
    { modules : Dict ModuleName (Module.Specification ta)
    }


{-| -}
emptySpecification : Specification ta
emptySpecification =
    { modules = Dict.empty
    }


{-| Type that represents a package definition.
-}
type alias Definition ta va =
    { modules : Dict ModuleName (AccessControlled (Module.Definition ta va))
    }


{-| An empty package definition.
-}
emptyDefinition : Definition ta va
emptyDefinition =
    { modules = Dict.empty
    }


{-| Look up a module specification by its path in a package specification.
-}
lookupModuleSpecification : Path -> Specification ta -> Maybe (Module.Specification ta)
lookupModuleSpecification modulePath packageSpec =
    packageSpec.modules
        |> Dict.get modulePath


{-| Look up a type specification by its module path and name in a package specification.
-}
lookupTypeSpecification : Path -> Name -> Specification ta -> Maybe (Type.Specification ta)
lookupTypeSpecification modulePath localName packageSpec =
    packageSpec
        |> lookupModuleSpecification modulePath
        |> Maybe.andThen (Module.lookupTypeSpecification localName)


{-| Look up a value specification by its module path and name in a package specification.
-}
lookupValueSpecification : Path -> Name -> Specification ta -> Maybe (Value.Specification ta)
lookupValueSpecification modulePath localName packageSpec =
    packageSpec
        |> lookupModuleSpecification modulePath
        |> Maybe.andThen (Module.lookupValueSpecification localName)


{-| -}
definitionToSpecification : Definition ta va -> Specification ta
definitionToSpecification def =
    { modules =
        def.modules
            |> Dict.toList
            |> List.filterMap
                (\( path, accessControlledModule ) ->
                    accessControlledModule
                        |> withPublicAccess
                        |> Maybe.map
                            (\moduleDef ->
                                ( path, Module.definitionToSpecification moduleDef )
                            )
                )
            |> Dict.fromList
    }


{-| -}
mapSpecificationAttributes : (ta -> tb) -> (va -> vb) -> Specification ta -> Specification tb
mapSpecificationAttributes tf vf spec =
    Specification
        (spec.modules
            |> Dict.map
                (\_ moduleSpec ->
                    Module.mapSpecificationAttributes tf vf moduleSpec
                )
        )


{-| -}
mapDefinitionAttributes : (ta -> tb) -> (va -> vb) -> Definition ta va -> Definition tb vb
mapDefinitionAttributes tf vf def =
    Definition
        (def.modules
            |> Dict.map
                (\_ moduleDef ->
                    AccessControlled moduleDef.access
                        (Module.mapDefinitionAttributes tf vf moduleDef.value)
                )
        )


{-| -}
eraseSpecificationAttributes : Specification ta -> Specification ()
eraseSpecificationAttributes spec =
    spec
        |> mapSpecificationAttributes (\_ -> ()) (\_ -> ())


{-| -}
eraseDefinitionAttributes : Definition ta va -> Definition () ()
eraseDefinitionAttributes def =
    def
        |> mapDefinitionAttributes (\_ -> ()) (\_ -> ())
