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


mapDeclaration : (Type a -> Type b) -> (Value a -> Value b) -> Declaration a -> Declaration b
mapDeclaration mapType mapValue decl =
    { types =
        decl.types
            |> Dict.map (\_ typeDecl -> Type.mapDeclaration mapType typeDecl)
    , values =
        decl.values
            |> Dict.map (\_ valueDecl -> Value.mapDeclaration mapType mapValue valueDecl)
    }


mapDefinition : (Type a -> Type b) -> (Value a -> Value b) -> Definition a -> Definition b
mapDefinition mapType mapValue def =
    { types =
        def.types
            |> Dict.map
                (\_ ac ->
                    ac
                        |> AccessControlled.map
                            (Type.mapDefinition mapType)
                )
    , values =
        def.values
            |> Dict.map (\_ ac -> ac |> AccessControlled.map (Value.mapDefinition mapType mapValue))
    }


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
