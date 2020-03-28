module Morphir.IR.Advanced.Package exposing
    ( Specification
    , Definition, emptyDefinition
    , definitionToSpecification, encodeDefinition, eraseDefinitionExtra, eraseSpecificationExtra
    )

{-| Tools to work with packages.

@docs Specification

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


{-| Type that represents a package specification.
-}
type alias Specification extra =
    { modules : Dict Path (Module.Specification extra)
    }


emptySpecification : Specification extra
emptySpecification =
    { modules = Dict.empty
    }


{-| Type that represents a package definition.
-}
type alias Definition extra =
    { dependencies : Dict Path (Specification extra)
    , modules : Dict Path (AccessControlled (Module.Definition extra))
    }


{-| An empty package definition.
-}
emptyDefinition : Definition extra
emptyDefinition =
    { dependencies = Dict.empty
    , modules = Dict.empty
    }


definitionToSpecification : Definition extra -> Specification extra
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


mapSpecification : (Type a -> Result e (Type b)) -> (Value a -> Value b) -> Specification a -> Result (List e) (Specification b)
mapSpecification mapType mapValue spec =
    let
        modulesResult : Result (List e) (Dict Path (Module.Specification b))
        modulesResult =
            spec.modules
                |> Dict.toList
                |> List.map
                    (\( modulePath, moduleSpec ) ->
                        moduleSpec
                            |> Module.mapSpecification mapType mapValue
                            |> Result.map (Tuple.pair modulePath)
                    )
                |> ResultList.toResult
                |> Result.map Dict.fromList
                |> Result.mapError List.concat
    in
    Result.map Specification modulesResult


eraseSpecificationExtra : Specification a -> Specification ()
eraseSpecificationExtra spec =
    spec
        |> mapSpecification
            (Type.mapTypeExtra (\_ -> ()) >> Ok)
            (Value.mapValueExtra (\_ -> ()))
        |> Result.withDefault emptySpecification


mapDefinition : (Type a -> Result e (Type b)) -> (Value a -> Value b) -> Definition a -> Result (List e) (Definition b)
mapDefinition mapType mapValue def =
    let
        dependenciesResult : Result (List e) (Dict Path (Specification b))
        dependenciesResult =
            def.dependencies
                |> Dict.toList
                |> List.map
                    (\( packagePath, packageSpec ) ->
                        packageSpec
                            |> mapSpecification mapType mapValue
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


encodeSpecification : (extra -> Encode.Value) -> Specification extra -> Encode.Value
encodeSpecification encodeExtra spec =
    Encode.object
        [ ( "modules"
          , spec.modules
                |> Dict.toList
                |> Encode.list
                    (\( moduleName, moduleSpec ) ->
                        Encode.object
                            [ ( "name", encodePath moduleName )
                            , ( "spec", Module.encodeSpecification encodeExtra moduleSpec )
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
                    (\( packageName, packageSpec ) ->
                        Encode.object
                            [ ( "name", encodePath packageName )
                            , ( "spec", encodeSpecification encodeExtra packageSpec )
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
