module Morphir.IR.Distribution exposing
    ( Distribution(..)
    , lookupModuleSpecification, lookupTypeSpecification, lookupValueSpecification, lookupBaseTypeName, lookupValueDefinition
    , lookupPackageSpecification, lookupPackageName, typeSpecifications, lookupTypeConstructor
    , resolveAliases, resolveType, resolveRecordConstructors
    , insertDependency
    )

{-| A distribution is a complete package of Morphir types and functions with all their dependencies.
`morphir-elm make` produces a JSON that represents a `Distribution`. We are planning to define different types of
distributions in the future but currently the only one is `Library`. A library contains the following pieces of
information:

  - The name of the library. This is the globally unique identifier of the package like the package name in NPM or the
    Group and Artifact ID in Maven.
  - All the library dependencies as a dictionary of package name and package specification. The package specification
    only contains type signatures, no implementations.
  - The package definition which contains all the module definitions included in the library. The package definition
    contains implementations as well, even ones that are not exposed.

@docs Distribution


# Lookups

@docs lookupModuleSpecification, lookupTypeSpecification, lookupValueSpecification, lookupBaseTypeName, lookupValueDefinition
@docs lookupPackageSpecification, lookupPackageName, typeSpecifications, lookupTypeConstructor
@docs resolveAliases, resolveType, resolveRecordConstructors


# Updates

@docs insertDependency

-}

import Dict exposing (Dict)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName, lookupModuleDefinition)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)


{-| Type that represents a package distribution. Currently the only distribution type we provide is a `Library`.
-}
type Distribution
    = Library PackageName (Dict PackageName (Package.Specification ())) (Package.Definition () (Type ()))


{-| Look up a module specification by package and module path in a distribution.
-}
lookupModuleSpecification : PackageName -> ModuleName -> Distribution -> Maybe (Module.Specification ())
lookupModuleSpecification packageName modulePath distribution =
    case distribution of
        Library libraryPackageName dependencies packageDef ->
            if packageName == libraryPackageName then
                packageDef
                    |> Package.definitionToSpecificationWithPrivate
                    |> Package.lookupModuleSpecification modulePath

            else
                dependencies
                    |> Dict.get packageName
                    |> Maybe.andThen (Package.lookupModuleSpecification modulePath)


{-| Look up a type specification by package, module and local name in a distribution.
-}
lookupTypeSpecification : FQName -> Distribution -> Maybe (Type.Specification ())
lookupTypeSpecification ( packageName, moduleName, localName ) distribution =
    distribution
        |> lookupModuleSpecification packageName moduleName
        |> Maybe.andThen (Module.lookupTypeSpecification localName)


{-| Look up the base type name following aliases by package, module and local name in a distribution.
-}
lookupBaseTypeName : FQName -> Distribution -> Maybe FQName
lookupBaseTypeName (( packageName, moduleName, localName ) as fQName) distribution =
    distribution
        |> lookupModuleSpecification packageName moduleName
        |> Maybe.andThen (Module.lookupTypeSpecification localName)
        |> Maybe.andThen
            (\typeSpec ->
                case typeSpec of
                    Type.TypeAliasSpecification _ (Type.Reference _ aliasFQName _) ->
                        lookupBaseTypeName aliasFQName distribution

                    _ ->
                        Just fQName
            )


{-| Look up a value specification by package, module and local name in a distribution.
-}
lookupValueSpecification : FQName -> Distribution -> Maybe (Value.Specification ())
lookupValueSpecification ( packageName, moduleName, localName ) distribution =
    distribution
        |> lookupModuleSpecification packageName moduleName
        |> Maybe.andThen (Module.lookupValueSpecification localName)


{-| Look up a value definition by qualified name in a distribution. The value will only be searched in the current
package.
-}
lookupValueDefinition : FQName -> Distribution -> Maybe (Value.Definition () (Type ()))
lookupValueDefinition ( packageName, moduleName, localName ) distribution =
    case distribution of
        Library pName _ packageDef ->
            -- For now we are only checking if the supplied FQN refers to the current package and only return a
            -- definition if it does. In the future we will likely include dependencies in the search. For now we only
            -- include the specifications of those so we cannot return the definition.
            if pName == packageName then
                packageDef
                    |> lookupModuleDefinition moduleName
                    |> Maybe.andThen (Module.lookupValueDefinition localName)

            else
                Nothing


{-| Get the package specification of a distribution.
-}
lookupPackageSpecification : Distribution -> Package.Specification ()
lookupPackageSpecification distribution =
    case distribution of
        Library _ _ packageDef ->
            packageDef
                |> Package.definitionToSpecificationWithPrivate
                |> Package.mapSpecificationAttributes (\_ -> ())


{-| Get the package name of a distribution.
-}
lookupPackageName : Distribution -> PackageName
lookupPackageName distribution =
    case distribution of
        Library packageName _ _ ->
            packageName


{-| Add a package specification as a dependency of this library.
-}
insertDependency : PackageName -> Package.Specification () -> Distribution -> Distribution
insertDependency dependencyPackageName dependencyPackageSpec distribution =
    case distribution of
        Library packageName dependencies packageDef ->
            Library packageName (dependencies |> Dict.insert dependencyPackageName dependencyPackageSpec) packageDef


{-| Get all type specifications.
-}
typeSpecifications : Distribution -> Dict FQName (Type.Specification ())
typeSpecifications (Library packageName dependencies packageDef) =
    let
        typeSpecsInDependencies : Dict FQName (Type.Specification ())
        typeSpecsInDependencies =
            dependencies
                |> Dict.toList
                |> List.concatMap
                    (\( pName, pSpec ) ->
                        pSpec.modules
                            |> Dict.toList
                            |> List.concatMap
                                (\( mName, mSpec ) ->
                                    mSpec.types
                                        |> Dict.toList
                                        |> List.map
                                            (\( tName, documentedTypeSpec ) ->
                                                ( ( pName, mName, tName ), documentedTypeSpec.value )
                                            )
                                )
                    )
                |> Dict.fromList

        typeSpecsInPackage : Dict FQName (Type.Specification ())
        typeSpecsInPackage =
            packageDef.modules
                |> Dict.toList
                |> List.concatMap
                    (\( mName, accessControlledModuleDef ) ->
                        accessControlledModuleDef.value.types
                            |> Dict.toList
                            |> List.map
                                (\( tName, accessControlledDocumentedTypeDef ) ->
                                    ( ( packageName, mName, tName ), Type.definitionToSpecification accessControlledDocumentedTypeDef.value.value )
                                )
                    )
                |> Dict.fromList
    in
    Dict.union
        typeSpecsInDependencies
        typeSpecsInPackage


{-| Look up a type constructor by fully-qualified name. Dependencies will be included in the search. The function
returns a tuple with the following elements:

  - The fully-qualified name of the type that this constructor belongs to.
  - The type arguments of the type.
  - The list of arguments (as name-type pairs) for this constructor.

-}
lookupTypeConstructor : FQName -> Distribution -> Maybe ( FQName, List Name, List ( Name, Type () ) )
lookupTypeConstructor ( packageName, moduleName, ctorName ) distro =
    distro
        |> lookupModuleSpecification packageName moduleName
        |> Maybe.andThen
            (\moduleSpec ->
                moduleSpec.types
                    |> Dict.toList
                    |> List.filterMap
                        (\( typeName, documentedTypeSpec ) ->
                            case documentedTypeSpec.value of
                                Type.CustomTypeSpecification typeArgs constructors ->
                                    constructors
                                        |> Dict.get ctorName
                                        |> Maybe.map
                                            (\constructorArgs ->
                                                ( ( packageName, moduleName, typeName ), typeArgs, constructorArgs )
                                            )

                                _ ->
                                    Nothing
                        )
                    |> List.head
            )


{-| Follow direct aliases until the leaf type is found.
-}
resolveAliases : FQName -> Distribution -> FQName
resolveAliases fQName distro =
    distro
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
resolveType : Type () -> Distribution -> Type ()
resolveType tpe distro =
    case tpe of
        Type.Variable a name ->
            Type.Variable a name

        Type.Reference _ fQName typeParams ->
            distro
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
            Type.Tuple a (elemTypes |> List.map (\t -> resolveType t distro))

        Type.Record a fields ->
            Type.Record a (fields |> List.map (\f -> { f | tpe = resolveType f.tpe distro }))

        Type.ExtensibleRecord a varName fields ->
            Type.ExtensibleRecord a varName (fields |> List.map (\f -> { f | tpe = resolveType f.tpe distro }))

        Type.Function a argType returnType ->
            Type.Function a (resolveType argType distro) (resolveType returnType distro)

        Type.Unit a ->
            Type.Unit a


{-| Replace record constructors with the corresponding record value.
-}
resolveRecordConstructors : Value ta va -> Distribution -> Value ta va
resolveRecordConstructors value distro =
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
                                distro
                                    |> lookupTypeSpecification fqn
                                    |> Maybe.andThen
                                        (\typeSpec ->
                                            case typeSpec of
                                                Type.TypeAliasSpecification _ (Type.Record _ fields) ->
                                                    Just
                                                        (Value.Record va <|
                                                            Dict.fromList (List.map2 Tuple.pair (fields |> List.map .name) args)
                                                        )

                                                _ ->
                                                    Nothing
                                        )

                            _ ->
                                Nothing

                    _ ->
                        Nothing
            )
