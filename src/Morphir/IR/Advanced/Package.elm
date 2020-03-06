module Morphir.IR.Advanced.Package exposing
    ( Declaration
    , Definition, emptyDefinition
    , definitionToDeclaration, encodeDefinition, eraseDeclarationExtra, eraseDefinitionExtra
    )

{-| Tools to work with packages.

@docs Declaration

@docs Definition, emptyDefinition

-}

import Dict exposing (Dict)
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.AccessControlled as AccessControlled exposing (AccessControlled, encodeAccessControlled, withPublicAccess)
import Morphir.IR.Advanced.Module as Module
import Morphir.IR.Advanced.Type as Type exposing (Type)
import Morphir.IR.Advanced.Value as Value exposing (Value)
import Morphir.IR.Path exposing (Path, encodePath)
import Morphir.IR.QName exposing (QName, encodeQName)


{-| Type that represents a package declaration.
-}
type alias Declaration extra =
    { modules : Dict Path (Module.Declaration extra)
    }


{-| Type that represents a package definition.
-}
type alias Definition extra =
    { dependencies : Dict Path (Declaration extra)
    , modules : Dict Path (AccessControlled (Module.Definition extra))
    }


{-| An empty package definition.
-}
emptyDefinition : Definition extra
emptyDefinition =
    { dependencies = Dict.empty
    , modules = Dict.empty
    }


definitionToDeclaration : Definition extra -> Declaration extra
definitionToDeclaration def =
    { modules =
        def.modules
            |> Dict.toList
            |> List.filterMap
                (\( path, accessControlledModule ) ->
                    accessControlledModule
                        |> withPublicAccess
                        |> Maybe.map
                            (\moduleDef ->
                                ( path, Module.definitionToDeclaration moduleDef )
                            )
                )
            |> Dict.fromList
    }


mapDeclaration : (Type a -> Type b) -> (Value a -> Value b) -> Declaration a -> Declaration b
mapDeclaration mapType mapValue decl =
    { modules =
        decl.modules
            |> Dict.map (\_ moduleDecl -> Module.mapDeclaration mapType mapValue moduleDecl)
    }


eraseDeclarationExtra : Declaration a -> Declaration ()
eraseDeclarationExtra =
    mapDeclaration
        (Type.mapTypeExtra (\_ -> ()))
        (Value.mapValueExtra (\_ -> ()))


mapDefinition : (Type a -> Type b) -> (Value a -> Value b) -> Definition a -> Definition b
mapDefinition mapType mapValue def =
    { dependencies =
        def.dependencies
            |> Dict.map (\_ packageDecl -> mapDeclaration mapType mapValue packageDecl)
    , modules =
        def.modules
            |> Dict.map (\_ ac -> ac |> AccessControlled.map (Module.mapDefinition mapType mapValue))
    }


eraseDefinitionExtra : Definition a -> Definition ()
eraseDefinitionExtra =
    mapDefinition
        (Type.mapTypeExtra (\_ -> ()))
        (Value.mapValueExtra (\_ -> ()))


encodeDeclaration : (extra -> Encode.Value) -> Declaration extra -> Encode.Value
encodeDeclaration encodeExtra decl =
    Encode.object
        [ ( "modules"
          , decl.modules
                |> Dict.toList
                |> Encode.list
                    (\( moduleName, moduleDecl ) ->
                        Encode.object
                            [ ( "name", encodePath moduleName )
                            , ( "decl", Module.encodeDeclaration encodeExtra moduleDecl )
                            ]
                    )
          )
        ]


encodeDefinition : (extra -> Encode.Value) -> Definition extra -> Encode.Value
encodeDefinition encodeExtra def =
    Encode.object
        [ ( "dependencies"
          , def.dependencies
                |> Dict.toList
                |> Encode.list
                    (\( packageName, packageDecl ) ->
                        Encode.object
                            [ ( "name", encodePath packageName )
                            , ( "decl", encodeDeclaration encodeExtra packageDecl )
                            ]
                    )
          )
        , ( "modules"
          , def.modules
                |> Dict.toList
                |> Encode.list
                    (\( moduleName, moduleDef ) ->
                        Encode.object
                            [ ( "name", encodePath moduleName )
                            , ( "def", encodeAccessControlled (Module.encodeDefinition encodeExtra) moduleDef )
                            ]
                    )
          )
        ]
