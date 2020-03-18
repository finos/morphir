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
import Morphir.ResultList as ResultList


{-| Type that represents a package declaration.
-}
type alias Declaration extra =
    { modules : Dict Path (Module.Declaration extra)
    }


emptyDeclaration : Declaration extra
emptyDeclaration =
    { modules = Dict.empty
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


mapDeclaration : (Type a -> Result e (Type b)) -> (Value a -> Value b) -> Declaration a -> Result (List e) (Declaration b)
mapDeclaration mapType mapValue decl =
    let
        modulesResult : Result (List e) (Dict Path (Module.Declaration b))
        modulesResult =
            decl.modules
                |> Dict.toList
                |> List.map
                    (\( modulePath, moduleDecl ) ->
                        moduleDecl
                            |> Module.mapDeclaration mapType mapValue
                            |> Result.map (Tuple.pair modulePath)
                    )
                |> ResultList.toResult
                |> Result.map Dict.fromList
                |> Result.mapError List.concat
    in
    Result.map Declaration modulesResult


eraseDeclarationExtra : Declaration a -> Declaration ()
eraseDeclarationExtra decl =
    decl
        |> mapDeclaration
            (Type.mapTypeExtra (\_ -> ()) >> Ok)
            (Value.mapValueExtra (\_ -> ()))
        |> Result.withDefault emptyDeclaration


mapDefinition : (Type a -> Result e (Type b)) -> (Value a -> Value b) -> Definition a -> Result (List e) (Definition b)
mapDefinition mapType mapValue def =
    let
        dependenciesResult : Result (List e) (Dict Path (Declaration b))
        dependenciesResult =
            def.dependencies
                |> Dict.toList
                |> List.map
                    (\( packagePath, packageDecl ) ->
                        packageDecl
                            |> mapDeclaration mapType mapValue
                            |> Result.map (Tuple.pair packagePath)
                    )
                |> ResultList.toResult
                |> Result.map Dict.fromList
                |> Result.mapError List.concat

        modulesResult : Result (List e) (Dict Path (AccessControlled (Module.Definition b)))
        modulesResult =
            def.modules
                |> Dict.toList
                |> List.map
                    (\( modulePath, moduleDef ) ->
                        moduleDef.value
                            |> Module.mapDefinition mapType mapValue
                            |> Result.map (AccessControlled moduleDef.access)
                            |> Result.map (Tuple.pair modulePath)
                    )
                |> ResultList.toResult
                |> Result.map Dict.fromList
                |> Result.mapError List.concat
    in
    Result.map2 Definition
        dependenciesResult
        modulesResult


eraseDefinitionExtra : Definition a -> Definition ()
eraseDefinitionExtra def =
    def
        |> mapDefinition
            (Type.mapTypeExtra (\_ -> ()) >> Ok)
            (Value.mapValueExtra (\_ -> ()))
        |> Result.withDefault emptyDefinition


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
