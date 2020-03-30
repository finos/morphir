module Morphir.IR.Module exposing
    ( Specification, Definition
    , encodeSpecification, encodeDefinition
    , definitionToSpecification, eraseSpecificationExtra, mapDefinition, mapSpecification
    )

{-| Modules are groups of types and values that belong together.

@docs Specification, Definition

@docs encodeSpecification, encodeDefinition

-}

import Dict exposing (Dict)
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.AccessControlled as AccessControlled exposing (AccessControlled, encodeAccessControlled, withPublicAccess)
import Morphir.IR.Name exposing (Name, encodeName)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.ResultList as ResultList


{-| Type that represents a module specification.
-}
type alias Specification extra =
    { types : Dict Name (Type.Specification extra)
    , values : Dict Name (Value.Specification extra)
    }


emptySpecification : Specification extra
emptySpecification =
    { types = Dict.empty
    , values = Dict.empty
    }


{-| Type that represents a module definition. It includes types and values.
-}
type alias Definition extra =
    { types : Dict Name (AccessControlled (Type.Definition extra))
    , values : Dict Name (AccessControlled (Value.Definition extra))
    }


definitionToSpecification : Definition extra -> Specification extra
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


eraseSpecificationExtra : Specification a -> Specification ()
eraseSpecificationExtra spec =
    spec
        |> mapSpecification
            (Type.mapTypeExtra (\_ -> ()) >> Ok)
            (Value.mapValueExtra (\_ -> ()))
        |> Result.withDefault emptySpecification


{-| -}
encodeSpecification : (extra -> Encode.Value) -> Specification extra -> Encode.Value
encodeSpecification encodeExtra spec =
    Encode.object
        [ ( "types"
          , spec.types
                |> Dict.toList
                |> Encode.list
                    (\( name, typeSpec ) ->
                        Encode.object
                            [ ( "name", encodeName name )
                            , ( "spec", Type.encodeSpecification encodeExtra typeSpec )
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
                            , ( "spec", Value.encodeSpecification encodeExtra valueSpec )
                            ]
                    )
          )
        ]


mapSpecification : (Type a -> Result e (Type b)) -> (Value a -> Value b) -> Specification a -> Result (List e) (Specification b)
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
                |> ResultList.toResult
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
                |> ResultList.toResult
                |> Result.map Dict.fromList
                |> Result.mapError List.concat
    in
    Result.map2 Specification
        typesResult
        valuesResult


mapDefinition : (Type a -> Result e (Type b)) -> (Value a -> Value b) -> Definition a -> Result (List e) (Definition b)
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
                |> ResultList.toResult
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
                |> ResultList.toResult
                |> Result.map Dict.fromList
                |> Result.mapError List.concat
    in
    Result.map2 Definition
        typesResult
        valuesResult


{-| -}
encodeDefinition : (extra -> Encode.Value) -> Definition extra -> Encode.Value
encodeDefinition encodeExtra def =
    Encode.object
        [ ( "types"
          , def.types
                |> Dict.toList
                |> Encode.list
                    (\( name, typeDef ) ->
                        Encode.object
                            [ ( "name", encodeName name )
                            , ( "def", encodeAccessControlled (Type.encodeDefinition encodeExtra) typeDef )
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
                            , ( "def", encodeAccessControlled (Value.encodeDefinition encodeExtra) valueDef )
                            ]
                    )
          )
        ]
