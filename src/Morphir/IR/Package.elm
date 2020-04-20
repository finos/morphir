module Morphir.IR.Package exposing
    ( Specification
    , Definition, emptyDefinition
    , PackagePath, definitionToSpecification, encodeDefinition, eraseDefinitionAttributes, eraseSpecificationAttributes
    )

{-| Tools to work with packages.

@docs Specification

@docs Definition, emptyDefinition

-}

import Dict exposing (Dict)
import Json.Encode as Encode
import Morphir.IR.AccessControlled exposing (AccessControlled, withPublicAccess)
import Morphir.IR.AccessControlled.Codec exposing (encodeAccessControlled)
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Path exposing (Path, encodePath)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.ListOfResults as ListOfResults


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


mapSpecification : (Type a -> Result e (Type b)) -> (Value a -> Result e (Value b)) -> Specification a -> Result (List e) (Specification b)
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
                |> ListOfResults.liftAllErrors
                |> Result.map Dict.fromList
                |> Result.mapError List.concat
    in
    Result.map Specification modulesResult


eraseSpecificationAttributes : Specification a -> Specification ()
eraseSpecificationAttributes spec =
    spec
        |> mapSpecification
            (Type.mapTypeAttributes (\_ -> ()) >> Ok)
            (Value.mapValueAttributes (\_ -> ()) >> Ok)
        |> Result.withDefault emptySpecification


mapDefinition : (Type a -> Result e (Type b)) -> (Value a -> Result e (Value b)) -> Definition a -> Result (List e) (Definition b)
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
                |> ListOfResults.liftAllErrors
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
                |> ListOfResults.liftAllErrors
                |> Result.map Dict.fromList
                |> Result.mapError List.concat
    in
    Result.map2 Definition
        dependenciesResult
        modulesResult


eraseDefinitionAttributes : Definition a -> Definition ()
eraseDefinitionAttributes def =
    def
        |> mapDefinition
            (Type.mapTypeAttributes (\_ -> ()) >> Ok)
            (Value.mapValueAttributes (\_ -> ()) >> Ok)
        |> Result.withDefault emptyDefinition


encodeSpecification : (a -> Encode.Value) -> Specification a -> Encode.Value
encodeSpecification encodeAttributes spec =
    Encode.object
        [ ( "modules"
          , spec.modules
                |> Dict.toList
                |> Encode.list
                    (\( moduleName, moduleSpec ) ->
                        Encode.object
                            [ ( "name", encodePath moduleName )
                            , ( "spec", Module.encodeSpecification encodeAttributes moduleSpec )
                            ]
                    )
          )
        ]


encodeDefinition : (a -> Encode.Value) -> Definition a -> Encode.Value
encodeDefinition encodeAttributes def =
    Encode.object
        [ ( "dependencies"
          , def.dependencies
                |> Dict.toList
                |> Encode.list
                    (\( packageName, packageSpec ) ->
                        Encode.object
                            [ ( "name", encodePath packageName )
                            , ( "spec", encodeSpecification encodeAttributes packageSpec )
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
                            , ( "def", encodeAccessControlled (Module.encodeDefinition encodeAttributes) moduleDef )
                            ]
                    )
          )
        ]
