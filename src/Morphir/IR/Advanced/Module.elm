module Morphir.IR.Advanced.Module exposing
    ( Declaration, Definition
    , encodeDeclaration, encodeDefinition
    , definitionToDeclaration, mapDeclaration, mapDefinition
    )

{-| Modules are groups of types and values that belong together.

@docs Declaration, Definition

@docs encodeDeclaration, encodeDefinition

-}

import Dict exposing (Dict)
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.AccessControlled as AccessControlled exposing (AccessControlled, encodeAccessControlled, withPublicAccess)
import Morphir.IR.Advanced.Type as Type exposing (Type)
import Morphir.IR.Advanced.Value as Value exposing (Value)
import Morphir.IR.Name exposing (Name, encodeName)
import Morphir.ResultList as ResultList


{-| Type that represents a module declaration.
-}
type alias Declaration extra =
    { types : Dict Name (Type.Declaration extra)
    , values : Dict Name (Value.Declaration extra)
    }


{-| Type that represents a module definition. It includes types and values.
-}
type alias Definition extra =
    { types : Dict Name (AccessControlled (Type.Definition extra))
    , values : Dict Name (AccessControlled (Value.Definition extra))
    }


definitionToDeclaration : Definition extra -> Declaration extra
definitionToDeclaration def =
    { types =
        def.types
            |> Dict.toList
            |> List.filterMap
                (\( path, accessControlledType ) ->
                    accessControlledType
                        |> withPublicAccess
                        |> Maybe.map
                            (\typeDef ->
                                ( path, Type.definitionToDeclaration typeDef )
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
    --                                 ( path, Value.definitionToDeclaration valueDef )
    --                             )
    --                 )
    --             |> Dict.fromList
    }


{-| -}
encodeDeclaration : (extra -> Encode.Value) -> Declaration extra -> Encode.Value
encodeDeclaration encodeExtra decl =
    Encode.object
        [ ( "types"
          , decl.types
                |> Dict.toList
                |> Encode.list
                    (\( name, typeDecl ) ->
                        Encode.object
                            [ ( "name", encodeName name )
                            , ( "decl", Type.encodeDeclaration encodeExtra typeDecl )
                            ]
                    )
          )
        , ( "values"
          , decl.values
                |> Dict.toList
                |> Encode.list
                    (\( name, valueDecl ) ->
                        Encode.object
                            [ ( "name", encodeName name )
                            , ( "decl", Value.encodeDeclaration encodeExtra valueDecl )
                            ]
                    )
          )
        ]


mapDeclaration : (Type a -> Result e (Type b)) -> (Value a -> Value b) -> Declaration a -> Result (List e) (Declaration b)
mapDeclaration mapType mapValue decl =
    let
        typesResult : Result (List e) (Dict Name (Type.Declaration b))
        typesResult =
            decl.types
                |> Dict.toList
                |> List.map
                    (\( typeName, typeDecl ) ->
                        typeDecl
                            |> Type.mapDeclaration mapType
                            |> Result.map (Tuple.pair typeName)
                    )
                |> ResultList.toResult
                |> Result.map Dict.fromList
                |> Result.mapError List.concat

        valuesResult : Result (List e) (Dict Name (Value.Declaration b))
        valuesResult =
            decl.values
                |> Dict.toList
                |> List.map
                    (\( valueName, valueDecl ) ->
                        valueDecl
                            |> Value.mapDeclaration mapType mapValue
                            |> Result.map (Tuple.pair valueName)
                    )
                |> ResultList.toResult
                |> Result.map Dict.fromList
                |> Result.mapError List.concat
    in
    Result.map2 Declaration
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
