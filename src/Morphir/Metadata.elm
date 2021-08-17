module Morphir.Metadata exposing
    ( Metadata
    , mapDistribution
    , getTypes, getEnums, getBaseTypes, getAliases, getDocumentation
    )

{-| The Metadata module analyses a distribution for the type of metadata information that would be helpful in
automating things like data dictionaries, lineage tracking, and the such.


# Types

@docs Metadata


# Processing

@docs mapDistribution, mapPackageDefinition, mapModuleTypes, mapModuleValues, mapTypeDefinition, mapValueDefinition


# Utilities

@docs getTypes, getEnums, getBaseTypes, getAliases, getDocumentation

-}

import Dict exposing (Dict)
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled, withPublicAccess)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Module as Module
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.Scala.AST exposing (Documented)


{-| Structure for holding metadata information from processing the distribution.
-}
type Metadata ta
    = Metadata (Types ta) Enums BaseTypes Aliases


{-| The registry of types through entire distribution.
-}
type alias Types ta =
    Dict FQName (Documented (Type.Definition ta))


{-| The registry of enums through the entire distribution.
An enum is identified as any union type that has only non-argument options.
-}
type alias Enums =
    Dict FQName (List Name)


{-| The registry of base types through the entire distribution.
A base type is any union type that has only one single argument option.
-}
type alias BaseTypes =
    Dict FQName FQName


{-| The registry of aliases through the entire distribution.
An alias is any type alias that aliases a non-record type.
-}
type alias Aliases =
    Dict FQName FQName


{-| Access function for getting the type registry from a Metadata structure.
-}
getTypes : Metadata ta -> Types ta
getTypes meta =
    case meta of
        Metadata types _ _ _ ->
            types


{-| Access function for getting the full type registry from a Metadata structure.
-}
getDocumentation : Metadata ta -> FQName -> Maybe String
getDocumentation meta fqn =
    getTypes meta
        |> Dict.get fqn
        |> Maybe.map .doc
        |> Maybe.withDefault Nothing
        |> Maybe.map String.trim


{-| Access function for getting the enum registry from a Metadata structure.
-}
getEnums : Metadata ta -> Enums
getEnums meta =
    case meta of
        Metadata _ enums _ _ ->
            enums


{-| Access function for getting the base type registry from a Metadata structure.
-}
getBaseTypes : Metadata ta -> BaseTypes
getBaseTypes meta =
    case meta of
        Metadata _ _ baseTypes _ ->
            baseTypes


{-| Access function for getting the alias type registry from a Metadata structure.
-}
getAliases : Metadata ta -> Aliases
getAliases meta =
    case meta of
        Metadata _ _ _ aliases ->
            aliases


{-| Process this distribution into a Metadata structure.
-}
mapDistribution : Distribution -> Metadata ()
mapDistribution distro =
    case distro of
        Distribution.Library packageName _ packageDef ->
            mapPackageDefinition packageName packageDef


{-| Process this package into a Metadata structure.
-}
mapPackageDefinition : Package.PackageName -> Package.Definition ta va -> Metadata ta
mapPackageDefinition packageName packageDef =
    let
        typeList =
            packageDef.modules
                |> Dict.toList
                |> List.concatMap
                    (\( moduleName, accessControlledModuleDef ) ->
                        mapModuleTypes packageName moduleName accessControlledModuleDef.value
                    )

        types =
            typeList
                |> Dict.fromList

        enums =
            typeList
                |> List.filterMap
                    (\( k, v ) ->
                        let
                            es =
                                asEnum v.value
                        in
                        if List.isEmpty es then
                            Nothing

                        else
                            Just ( k, es )
                    )
                |> Dict.fromList

        bases =
            typeList
                |> List.filterMap
                    (\( k, v ) ->
                        let
                            bs =
                                asBaseType v.value
                        in
                        bs |> Maybe.map (\b -> ( k, b ))
                    )
                |> Dict.fromList

        aliases =
            typeList
                |> List.filterMap
                    (\( k, v ) ->
                        let
                            bs =
                                asAlias v.value
                        in
                        bs |> Maybe.map (\b -> ( k, b ))
                    )
                |> Dict.fromList
    in
    Metadata types enums bases aliases


{-| Process this module to collect the types used produced by it.
-}
mapModuleTypes : Package.PackageName -> Module.ModuleName -> Module.Definition ta va -> List ( FQName, Documented (Type.Definition ta) )
mapModuleTypes packageName moduleName moduleDef =
    moduleDef.types
        |> Dict.toList
        |> List.map
            (\( typeName, accessControlledDocumentedTypeDef ) ->
                mapTypeDefinition packageName moduleName typeName accessControlledDocumentedTypeDef.value.value accessControlledDocumentedTypeDef.value.doc
            )


{-| Process a type since there are a lot of variations.
-}
mapTypeDefinition : Package.PackageName -> Module.ModuleName -> Name -> Type.Definition ta -> String -> ( FQName, Documented (Type.Definition ta) )
mapTypeDefinition packageName moduleName typeName typeDef documentation =
    let
        fqn =
            ( packageName, moduleName, typeName )

        mDocumentation =
            documentation
                |> String.trim
                |> (\s ->
                        if String.isEmpty s then
                            Nothing

                        else
                            Just s
                   )
    in
    ( fqn, Documented mDocumentation typeDef )


{-| Decides whether a union type is an enum by ensuring it only has no-arg constructors.
-}
isEnum : Dict a (List b) -> Bool
isEnum constructors =
    constructors
        |> Dict.toList
        |> List.all
            (\( name, args ) ->
                List.isEmpty args
            )


{-| Decides whether a type is an enum through Maybe.
-}
asEnum : Type.Definition ta -> List Name
asEnum typeDef =
    case typeDef of
        Type.CustomTypeDefinition _ accessControlledCtors ->
            case accessControlledCtors |> withPublicAccess of
                Just constructors ->
                    if isEnum constructors then
                        constructors
                            |> Dict.keys

                    else
                        []

                _ ->
                    []

        _ ->
            []


{-| Decides whether a type is a base type through Maybe.
-}
asBaseType : Type.Definition ta -> Maybe FQName
asBaseType typeDef =
    case typeDef of
        Type.CustomTypeDefinition _ accessControlledCtors ->
            let
                values =
                    accessControlledCtors
                        |> withPublicAccess
                        |> Maybe.map Dict.values
                        |> Maybe.withDefault []
            in
            case values of
                [ [ ( name, Type.Reference _ fqn _ ) ] ] ->
                    Just fqn

                _ ->
                    Nothing

        _ ->
            Nothing


{-| Decides whether a type is an alias through Maybe.
-}
asAlias : Type.Definition ta -> Maybe FQName
asAlias typeDef =
    case typeDef of
        -- This is a type alias, so we want to get that as a type and register the base type as well.
        Type.TypeAliasDefinition _ (Type.Reference _ aliasFQN _) ->
            Just aliasFQN

        _ ->
            Nothing
