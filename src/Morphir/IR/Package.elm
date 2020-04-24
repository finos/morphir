module Morphir.IR.Package exposing
    ( Specification
    , Definition, emptyDefinition
    , PackagePath, definitionToSpecification, eraseDefinitionAttributes, eraseSpecificationAttributes
    )

{-| Tools to work with packages.

@docs Specification

@docs Definition, emptyDefinition

-}

import Dict exposing (Dict)
import Morphir.IR.AccessControlled exposing (AccessControlled, withPublicAccess)
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Path exposing (Path)


type alias PackagePath =
    Path


{-| Type that represents a package specification.
-}
type alias Specification a =
    { modules : Dict ModulePath (Module.Specification a)
    }


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


mapSpecificationAttributes : (a -> b) -> Specification a -> Specification b
mapSpecificationAttributes f spec =
    Specification
        (spec.modules
            |> Dict.map
                (\_ moduleSpec ->
                    Module.mapSpecificationAttributes f moduleSpec
                )
        )


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


eraseSpecificationAttributes : Specification a -> Specification ()
eraseSpecificationAttributes spec =
    spec
        |> mapSpecificationAttributes (\_ -> ())


eraseDefinitionAttributes : Definition a -> Definition ()
eraseDefinitionAttributes def =
    def
        |> mapDefinitionAttributes (\_ -> ())
