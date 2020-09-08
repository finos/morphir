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
    ( Distribution(..)
    , Specification
    , Definition, emptyDefinition
    , PackagePath, definitionToSpecification, eraseDefinitionAttributes, eraseSpecificationAttributes
    )

{-| Tools to work with packages.

@docs Distribution

@docs Specification

@docs Definition, emptyDefinition

@docs PackagePath, definitionToSpecification, eraseDefinitionAttributes, eraseSpecificationAttributes

-}

import Dict exposing (Dict)
import Morphir.IR.AccessControlled exposing (AccessControlled, withPublicAccess)
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Path exposing (Path)


{-| Type that represents a package distribution. A distribution contains all the necessary information to consume a
package.
-}
type Distribution
    = Library PackagePath (Definition () ())


{-| -}
type alias PackagePath =
    Path


{-| Type that represents a package specification.
-}
type alias Specification ta va =
    { modules : Dict ModulePath (Module.Specification ta va)
    }


{-| -}
emptySpecification : Specification ta va
emptySpecification =
    { modules = Dict.empty
    }


{-| Type that represents a package definition.
-}
type alias Definition ta va =
    { dependencies : Dict PackagePath (Specification ta va)
    , modules : Dict ModulePath (AccessControlled (Module.Definition ta va))
    }


{-| An empty package definition.
-}
emptyDefinition : Definition ta va
emptyDefinition =
    { dependencies = Dict.empty
    , modules = Dict.empty
    }


{-| -}
definitionToSpecification : Definition ta va -> Specification ta va
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
mapSpecificationAttributes : (ta -> tb) -> (va -> vb) -> Specification ta va -> Specification tb vb
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
        (def.dependencies
            |> Dict.map
                (\_ packageSpec ->
                    mapSpecificationAttributes tf vf packageSpec
                )
        )
        (def.modules
            |> Dict.map
                (\_ moduleDef ->
                    AccessControlled moduleDef.access
                        (Module.mapDefinitionAttributes tf vf moduleDef.value)
                )
        )


{-| -}
eraseSpecificationAttributes : Specification ta va -> Specification () ()
eraseSpecificationAttributes spec =
    spec
        |> mapSpecificationAttributes (\_ -> ()) (\_ -> ())


{-| -}
eraseDefinitionAttributes : Definition ta va -> Definition () ()
eraseDefinitionAttributes def =
    def
        |> mapDefinitionAttributes (\_ -> ()) (\_ -> ())
