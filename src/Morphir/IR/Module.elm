module Morphir.IR.Module exposing
    ( Specification, Definition
    , ModulePath, definitionToSpecification, eraseSpecificationAttributes, mapDefinitionAttributes, mapSpecificationAttributes
    )

{-| Modules are groups of types and values that belong together.

@docs Specification, Definition
@docs ModulePath, definitionToSpecification, eraseSpecificationAttributes, mapDefinitionAttributes, mapSpecificationAttributes

-}

import Dict exposing (Dict)
import Morphir.IR.AccessControlled exposing (AccessControlled, withPublicAccess)
import Morphir.IR.Documented as Documented exposing (Documented)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)


{-| -}
type alias ModulePath =
    Path


{-| Type that represents a module specification.
-}
type alias Specification a =
    { types : Dict Name (Documented (Type.Specification a))
    , values : Dict Name (Value.Specification a)
    }


{-| -}
emptySpecification : Specification a
emptySpecification =
    { types = Dict.empty
    , values = Dict.empty
    }


{-| Type that represents a module definition. It includes types and values.
-}
type alias Definition a =
    { types : Dict Name (AccessControlled (Documented (Type.Definition a)))
    , values : Dict Name (AccessControlled (Value.Definition a))
    }


{-| -}
definitionToSpecification : Definition a -> Specification a
definitionToSpecification def =
    { types =
        def.types
            |> Dict.toList
            |> List.filterMap
                (\( path, accessControlledType ) ->
                    accessControlledType
                        |> withPublicAccess
                        |> Maybe.map
                            (\typeDef ->
                                ( path, typeDef |> Documented.map Type.definitionToSpecification )
                            )
                )
            |> Dict.fromList
    , values = Dict.empty

    -- TODO: implement for values
    --         def.values
    --             |> Dict.toList
    --             |> List.filterMap
    --                 (\( path, accessControlledValue ) ->
    --                     accessControlledValue
    --                         |> withPublicAccess
    --                         |> Maybe.map
    --                             (\valueDef ->
    --                                 ( path, Value.definitionToSpecification valueDef )
    --                             )
    --                 )
    --             |> Dict.fromList
    }


{-| -}
eraseSpecificationAttributes : Specification a -> Specification ()
eraseSpecificationAttributes spec =
    spec
        |> mapSpecificationAttributes (\_ -> ())


{-| -}
mapSpecificationAttributes : (a -> b) -> Specification a -> Specification b
mapSpecificationAttributes f spec =
    Specification
        (spec.types
            |> Dict.map
                (\_ typeSpec ->
                    typeSpec |> Documented.map (Type.mapSpecificationAttributes f)
                )
        )
        (spec.values
            |> Dict.map
                (\_ valueSpec ->
                    Value.mapSpecificationAttributes f valueSpec
                )
        )


{-| -}
mapDefinitionAttributes : (a -> b) -> Definition a -> Definition b
mapDefinitionAttributes f def =
    Definition
        (def.types
            |> Dict.map
                (\_ typeDef ->
                    AccessControlled typeDef.access
                        (typeDef.value |> Documented.map (Type.mapDefinitionAttributes f))
                )
        )
        (def.values
            |> Dict.map
                (\_ valueDef ->
                    AccessControlled valueDef.access
                        (Value.mapDefinitionAttributes f valueDef.value)
                )
        )
