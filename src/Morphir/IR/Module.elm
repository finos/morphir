module Morphir.IR.Module exposing
    ( Specification, Definition
    , encodeSpecification, encodeDefinition
    , ModulePath, definitionToSpecification, eraseSpecificationAttributes, mapDefinition, mapSpecification
    )

{-| Modules are groups of types and values that belong together.

@docs Specification, Definition

@docs encodeSpecification, encodeDefinition

-}

import Dict exposing (Dict)
import Json.Encode as Encode
import Morphir.IR.AccessControlled exposing (AccessControlled, encodeAccessControlled, withPublicAccess)
import Morphir.IR.Name exposing (Name, encodeName)
import Morphir.IR.Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.ListOfResults as ListOfResults


type alias ModulePath =
    Path


{-| Type that represents a module specification.
-}
type alias Specification a =
    { types : Dict Name (Type.Specification a)
    , values : Dict Name (Value.Specification a)
    }


emptySpecification : Specification a
emptySpecification =
    { types = Dict.empty
    , values = Dict.empty
    }


{-| Type that represents a module definition. It includes types and values.
-}
type alias Definition a =
    { types : Dict Name (AccessControlled (Type.Definition a))
    , values : Dict Name (AccessControlled (Value.Definition a))
    }


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
                                ( path, Type.definitionToSpecification typeDef )
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


eraseSpecificationAttributes : Specification a -> Specification ()
eraseSpecificationAttributes spec =
    spec
        |> mapSpecification
            (Type.mapTypeAttributes (\_ -> ()) >> Ok)
            (Value.mapValueAttributes (\_ -> ()) >> Ok)
        |> Result.withDefault emptySpecification


{-| -}
encodeSpecification : (a -> Encode.Value) -> Specification a -> Encode.Value
encodeSpecification encodeAttributes spec =
    Encode.object
        [ ( "types"
          , spec.types
                |> Dict.toList
                |> Encode.list
                    (\( name, typeSpec ) ->
                        Encode.object
                            [ ( "name", encodeName name )
                            , ( "spec", Type.encodeSpecification encodeAttributes typeSpec )
                            ]
                    )
          )
        , ( "values"
          , spec.values
                |> Dict.toList
                |> Encode.list
                    (\( name, valueSpec ) ->
                        Encode.object
                            [ ( "name", encodeName name )
                            , ( "spec", Value.encodeSpecification encodeAttributes valueSpec )
                            ]
                    )
          )
        ]


mapSpecification : (Type a -> Result e (Type b)) -> (Value a -> Result e (Value b)) -> Specification a -> Result (List e) (Specification b)
mapSpecification mapType mapValue spec =
    let
        typesResult : Result (List e) (Dict Name (Type.Specification b))
        typesResult =
            spec.types
                |> Dict.toList
                |> List.map
                    (\( typeName, typeSpec ) ->
                        typeSpec
                            |> Type.mapSpecification mapType
                            |> Result.map (Tuple.pair typeName)
                    )
                |> ListOfResults.toResultOfList
                |> Result.map Dict.fromList
                |> Result.mapError List.concat

        valuesResult : Result (List e) (Dict Name (Value.Specification b))
        valuesResult =
            spec.values
                |> Dict.toList
                |> List.map
                    (\( valueName, valueSpec ) ->
                        valueSpec
                            |> Value.mapSpecification mapType mapValue
                            |> Result.map (Tuple.pair valueName)
                    )
                |> ListOfResults.toResultOfList
                |> Result.map Dict.fromList
                |> Result.mapError List.concat
    in
    Result.map2 Specification
        typesResult
        valuesResult


mapDefinition : (Type a -> Result e (Type b)) -> (Value a -> Result e (Value b)) -> Definition a -> Result (List e) (Definition b)
mapDefinition mapType mapValue def =
    let
        typesResult : Result (List e) (Dict Name (AccessControlled (Type.Definition b)))
        typesResult =
            def.types
                |> Dict.toList
                |> List.map
                    (\( typeName, typeDef ) ->
                        typeDef.value
                            |> Type.mapDefinition mapType
                            |> Result.map (AccessControlled typeDef.access)
                            |> Result.map (Tuple.pair typeName)
                    )
                |> ListOfResults.toResultOfList
                |> Result.map Dict.fromList
                |> Result.mapError List.concat

        valuesResult : Result (List e) (Dict Name (AccessControlled (Value.Definition b)))
        valuesResult =
            def.values
                |> Dict.toList
                |> List.map
                    (\( valueName, valueDef ) ->
                        valueDef.value
                            |> Value.mapDefinition mapType mapValue
                            |> Result.map (AccessControlled valueDef.access)
                            |> Result.map (Tuple.pair valueName)
                    )
                |> ListOfResults.toResultOfList
                |> Result.map Dict.fromList
                |> Result.mapError List.concat
    in
    Result.map2 Definition
        typesResult
        valuesResult


{-| -}
encodeDefinition : (a -> Encode.Value) -> Definition a -> Encode.Value
encodeDefinition encodeAttributes def =
    Encode.object
        [ ( "types"
          , def.types
                |> Dict.toList
                |> Encode.list
                    (\( name, typeDef ) ->
                        Encode.object
                            [ ( "name", encodeName name )
                            , ( "def", encodeAccessControlled (Type.encodeDefinition encodeAttributes) typeDef )
                            ]
                    )
          )
        , ( "values"
          , def.values
                |> Dict.toList
                |> Encode.list
                    (\( name, valueDef ) ->
                        Encode.object
                            [ ( "name", encodeName name )
                            , ( "def", encodeAccessControlled (Value.encodeDefinition encodeAttributes) valueDef )
                            ]
                    )
          )
        ]
