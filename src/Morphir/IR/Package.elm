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
    = Library PackagePath (Definition ())


{-| -}
type alias PackagePath =
    Path


{-| Type that represents a package specification.
-}
type alias Specification a =
    { modules : Dict ModulePath (Module.Specification a)
    }


{-| -}
emptySpecification : Specification a
emptySpecification =
    { modules = Dict.empty
    }


{-| Type that represents a package definition.
-}
type alias Definition a =
    { dependencies : Dict PackagePath (Specification a)
    , modules : Dict ModulePath (AccessControlled (Module.Definition a))
    }


{-| An empty package definition.
-}
emptyDefinition : Definition a
emptyDefinition =
    { dependencies = Dict.empty
    , modules = Dict.empty
    }


{-| -}
definitionToSpecification : Definition a -> Specification a
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
mapSpecificationAttributes : (a -> b) -> Specification a -> Specification b
mapSpecificationAttributes f spec =
    Specification
        (spec.modules
            |> Dict.map
                (\_ moduleSpec ->
                    Module.mapSpecificationAttributes f moduleSpec
                )
        )


{-| -}
mapDefinitionAttributes : (a -> b) -> Definition a -> Definition b
mapDefinitionAttributes f def =
    Definition
        (def.dependencies
            |> Dict.map
                (\_ packageSpec ->
                    mapSpecificationAttributes f packageSpec
                )
        )
        (def.modules
            |> Dict.map
                (\_ moduleDef ->
                    AccessControlled moduleDef.access
                        (Module.mapDefinitionAttributes f moduleDef.value)
                )
        )


{-| -}
eraseSpecificationAttributes : Specification a -> Specification ()
eraseSpecificationAttributes spec =
    spec
        |> mapSpecificationAttributes (\_ -> ())


{-| -}
eraseDefinitionAttributes : Definition a -> Definition ()
eraseDefinitionAttributes def =
    def
        |> mapDefinitionAttributes (\_ -> ())
