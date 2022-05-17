{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}


module Morphir.IR exposing
    ( IR
    , fromPackageSpecifications, fromDistribution
    , typeSpecifications
    , lookupTypeSpecification, lookupTypeConstructor, lookupValueSpecification, lookupValueDefinition
    , empty, resolveAliases, resolveType, resolveRecordConstructors
    )

{-| This module contains data structures and functions to make working with the IR easier and more efficient.

@docs IR


# Conversions

@docs fromPackageSpecifications, fromDistribution


# Lookups

@docs typeSpecifications
@docs lookupTypeSpecification, lookupTypeConstructor, lookupValueSpecification, lookupValueDefinition


# Utilities

@docs empty, resolveAliases, resolveType, resolveRecordConstructors

-}

import Dict exposing (Dict)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)


{-| Data structure to store types and values efficiently.
-}
type alias IR =
    { valueSpecifications : Dict FQName (Value.Specification ())
    , valueDefinitions : Dict FQName (Value.Definition () (Type ()))
    , typeSpecifications : Dict FQName (Type.Specification ())
    , typeConstructors : Dict FQName ( FQName, List Name, List ( Name, Type () ) )
    }


{-| Creates and empty IR with no types or values.
-}
empty : IR
empty =
    { valueSpecifications = Dict.empty
    , valueDefinitions = Dict.empty
    , typeSpecifications = Dict.empty
    , typeConstructors = Dict.empty
    }


{-| Turn a `Distribution` into an `IR`. The `Distribution` data type is optimized for transfer while the `IR` data type
is optimized for efficient in-memory processing.
-}
fromDistribution : Distribution -> IR
fromDistribution (Distribution.Library libraryName dependencies packageDef) =
    let
        packageSpecs : Dict PackageName (Package.Specification ())
        packageSpecs =
            dependencies
                |> Dict.insert libraryName (packageDef |> Package.definitionToSpecificationWithPrivate)

        specificationsOnly : IR
        specificationsOnly =
            fromPackageSpecifications packageSpecs

        packageValueDefinitions : Dict FQName (Value.Definition () (Type ()))
        packageValueDefinitions =
            packageDef.modules
                |> Dict.toList
                |> List.concatMap
                    (\( moduleName, moduleDef ) ->
                        moduleDef.value.values
                            |> Dict.toList
                            |> List.map
                                (\( valueName, valueDef ) ->
                                    ( ( libraryName, moduleName, valueName ), valueDef.value.value )
                                )
                    )
                |> Dict.fromList
    in
    { specificationsOnly
        | valueDefinitions = packageValueDefinitions
    }


{-| Turn a dictionary of package specifications into an `IR`.
-}
fromPackageSpecifications : Dict PackageName (Package.Specification ()) -> IR
fromPackageSpecifications packageSpecs =
    let
        packageValueSpecifications : PackageName -> Package.Specification () -> List ( FQName, Value.Specification () )
        packageValueSpecifications packageName packageSpec =
            packageSpec.modules
                |> Dict.toList
                |> List.concatMap
                    (\( moduleName, moduleSpec ) ->
                        moduleSpec.values
                            |> Dict.toList
                            |> List.map
                                (\( valueName, valueSpec ) ->
                                    ( ( packageName, moduleName, valueName ), valueSpec.value )
                                )
                    )

        packageTypeSpecifications : PackageName -> Package.Specification () -> List ( FQName, Type.Specification () )
        packageTypeSpecifications packageName packageSpec =
            packageSpec.modules
                |> Dict.toList
                |> List.concatMap
                    (\( moduleName, moduleSpec ) ->
                        moduleSpec.types
                            |> Dict.toList
                            |> List.map
                                (\( typeName, typeSpec ) ->
                                    ( ( packageName, moduleName, typeName ), typeSpec.value )
                                )
                    )

        packageTypeConstructors : PackageName -> Package.Specification () -> List ( FQName, ( FQName, List Name, List ( Name, Type () ) ) )
        packageTypeConstructors packageName packageSpec =
            packageSpec.modules
                |> Dict.toList
                |> List.concatMap
                    (\( moduleName, moduleSpec ) ->
                        moduleSpec.types
                            |> Dict.toList
                            |> List.concatMap
                                (\( typeName, typeSpec ) ->
                                    case typeSpec.value of
                                        Type.CustomTypeSpecification params constructors ->
                                            constructors
                                                |> Dict.toList
                                                |> List.map
                                                    (\( ctorName, ctorArgs ) ->
                                                        ( ( packageName, moduleName, ctorName ), ( ( packageName, moduleName, typeName ), params, ctorArgs ) )
                                                    )

                                        _ ->
                                            []
                                )
                    )
    in
    { valueSpecifications = flattenPackages packageSpecs packageValueSpecifications
    , valueDefinitions = Dict.empty
    , typeSpecifications = flattenPackages packageSpecs packageTypeSpecifications
    , typeConstructors = flattenPackages packageSpecs packageTypeConstructors
    }


flattenPackages : Dict PackageName p -> (PackageName -> p -> List ( FQName, r )) -> Dict FQName r
flattenPackages packages f =
    packages
        |> Dict.toList
        |> List.concatMap
            (\( packageName, package ) ->
                f packageName package
            )
        |> Dict.fromList


{-| Get all type specifications.
-}
typeSpecifications : IR -> Dict FQName (Type.Specification ())
typeSpecifications ir =
    ir.typeSpecifications


{-| Look up a value specification by fully-qualified name. Dependencies will be included in the search.
-}
lookupValueSpecification : FQName -> IR -> Maybe (Value.Specification ())
lookupValueSpecification fqn ir =
    ir.valueSpecifications
        |> Dict.get fqn


{-| Look up a value definition by fully-qualified name. Dependencies will not be included in the search.
-}
lookupValueDefinition : FQName -> IR -> Maybe (Value.Definition () (Type ()))
lookupValueDefinition fqn ir =
    ir.valueDefinitions
        |> Dict.get fqn


{-| Look up a type specification by fully-qualified name. Dependencies will be included in the search.
-}
lookupTypeSpecification : FQName -> IR -> Maybe (Type.Specification ())
lookupTypeSpecification fqn ir =
    ir.typeSpecifications
        |> Dict.get fqn


{-| Look up a type constructor by fully-qualified name. Dependencies will be included in the search. The function
returns a tuple with the following elements:

  - The fully-qualified name of the type that this constructor belongs to.
  - The type arguments of the type.
  - The list of arguments (as name-type pairs) for this constructor.

-}
lookupTypeConstructor : FQName -> IR -> Maybe ( FQName, List Name, List ( Name, Type () ) )
lookupTypeConstructor fqn ir =
    ir.typeConstructors
        |> Dict.get fqn


{-| Follow direct aliases until the leaf type is found.
-}
resolveAliases : FQName -> IR -> FQName
resolveAliases fQName ir =
    ir
        |> lookupTypeSpecification fQName
        |> Maybe.map
            (\typeSpec ->
                case typeSpec of
                    Type.TypeAliasSpecification _ (Type.Reference _ aliasFQName _) ->
                        aliasFQName

                    _ ->
                        fQName
            )
        |> Maybe.withDefault fQName


{-| Fully resolve all type aliases in the type.
-}
resolveType : Type () -> IR -> Type ()
resolveType tpe ir =
    case tpe of
        Type.Variable a name ->
            Type.Variable a name

        Type.Reference _ fQName typeParams ->
            ir
                |> lookupTypeSpecification fQName
                |> Maybe.map
                    (\typeSpec ->
                        case typeSpec of
                            Type.TypeAliasSpecification typeParamNames targetType ->
                                Type.substituteTypeVariables
                                    (List.map2 Tuple.pair typeParamNames typeParams
                                        |> Dict.fromList
                                    )
                                    targetType

                            _ ->
                                tpe
                    )
                |> Maybe.withDefault tpe

        Type.Tuple a elemTypes ->
            Type.Tuple a (elemTypes |> List.map (\t -> resolveType t ir))

        Type.Record a fields ->
            Type.Record a (fields |> List.map (\f -> { f | tpe = resolveType f.tpe ir }))

        Type.ExtensibleRecord a varName fields ->
            Type.ExtensibleRecord a varName (fields |> List.map (\f -> { f | tpe = resolveType f.tpe ir }))

        Type.Function a argType returnType ->
            Type.Function a (resolveType argType ir) (resolveType returnType ir)

        Type.Unit a ->
            Type.Unit a


{-| Replace record constructors with the corresponding record value.
-}
resolveRecordConstructors : Value ta va -> IR -> Value ta va
resolveRecordConstructors value ir =
    value
        |> Value.rewriteValue
            (\v ->
                case v of
                    Value.Apply _ fun lastArg ->
                        let
                            ( bottomFun, args ) =
                                Value.uncurryApply fun lastArg
                        in
                        case bottomFun of
                            Value.Constructor va fqn ->
                                ir
                                    |> lookupTypeSpecification fqn
                                    |> Maybe.andThen
                                        (\typeSpec ->
                                            case typeSpec of
                                                Type.TypeAliasSpecification _ (Type.Record _ fields) ->
                                                    Just
                                                        (Value.Record va
                                                            (List.map2 Tuple.pair (fields |> List.map .name) args)
                                                        )

                                                _ ->
                                                    Nothing
                                        )

                            _ ->
                                Nothing

                    _ ->
                        Nothing
            )
