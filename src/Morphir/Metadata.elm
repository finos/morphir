module Morphir.Metadata exposing
   (Metadata, mapDistribution, getTypes, getEnums, getBaseTypes, getAliases)

{-| The Metadata module analyses a distribution to build a graph for dependency and lineage tracking purposes.
The goal is to understand data flow and to automate contribution to the types of products that are commonly used in
enterprises. The result of processing is a [Graph](#Graph), which is a collection of [Nodes](#Node) and [Edges](#Edge).


# Types

@docs Node, Verb, Edge, GraphEntry, Graph


# Processing

@docs mapDistribution, mapPackageDefinition, mapModuleTypes, mapModuleValues, mapTypeDefinition, mapValueDefinition


# Utilities

@docs graphEntryToComparable, nodeType, verbToString, nodeFQN

-}

import Dict exposing (Dict)
import Morphir.IR.AccessControlled exposing (Access(..), withPublicAccess)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Module as Module
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))



type Metadata ta =
    Metadata
        (Dict FQName (Type.Definition ta))
        (Dict FQName (List Name))
        (Dict FQName FQName)
        (Dict FQName FQName)

getTypes : Metadata ta -> Dict FQName (Type.Definition ta)
getTypes meta =
    case meta of
        Metadata types _ _ _ -> types

getEnums : Metadata ta -> Dict FQName (List Name)
getEnums meta =
    case meta of
        Metadata  _ enums _ _ -> enums

getBaseTypes : Metadata ta -> Dict  FQName FQName
getBaseTypes meta =
    case meta of
        Metadata  _ _ baseTypes _ -> baseTypes

getAliases : Metadata ta -> Dict  FQName FQName
getAliases meta =
    case meta of
        Metadata  _ _ _ aliases -> aliases

{-| Process this distribution into a Graph of its packages.
-}
mapDistribution : Distribution -> Metadata ()
mapDistribution distro =
    case distro of
        Distribution.Library packageName _ packageDef ->
            mapPackageDefinition packageName packageDef


{-| Process this package into a Graph of its modules. We take two passes to the IR. The first collects all of the
types and the second processes the functions and their relationships to those types.
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
                |> List.filterMap (\(k,v) ->
                    let
                        es = asEnum v
                    in
                        if List.isEmpty es then
                            Nothing
                        else
                            Just (k, es)
                )
                |> Dict.fromList

        bases =
            typeList
                |> List.filterMap (\(k,v) ->
                    let
                        bs = asBaseType v
                    in
                        bs |> Maybe.map (\b -> (k, b))
                )
                |> Dict.fromList

        aliases =
            typeList
                |> List.filterMap (\(k,v) ->
                    let
                        bs = asAlias v
                    in
                        bs |> Maybe.map (\b -> (k, b))
                )
                |> Dict.fromList
    in
        Metadata types enums bases aliases

{-| Process this module to collect the types used and produced by it.
-}
mapModuleTypes : Package.PackageName -> Module.ModuleName -> Module.Definition ta va -> List (FQName, Type.Definition ta)
mapModuleTypes packageName moduleName moduleDef =
    moduleDef.types
        |> Dict.toList
        |> List.map
            (\( typeName, accessControlledDocumentedTypeDef ) ->
                mapTypeDefinition packageName moduleName typeName accessControlledDocumentedTypeDef.value.value
            )

{-| Process a type since there are a lot of variations.
-}
mapTypeDefinition : Package.PackageName -> Module.ModuleName -> Name -> Type.Definition ta -> (FQName, Type.Definition ta)
mapTypeDefinition packageName moduleName typeName typeDef =
    let
        fqn =
            ( packageName, moduleName, typeName )
    in
    (fqn, typeDef)


isEnum : Dict a (List b) -> Bool
isEnum constructors =
    constructors
        |> Dict.toList
        |> List.all
            (\( name, args ) ->
                List.isEmpty args
            )


asEnum : Type.Definition ta ->  (List Name)
asEnum typeDef =
    case typeDef of
        Type.CustomTypeDefinition _ accessControlledCtors ->
            case accessControlledCtors |> withPublicAccess of
                Just constructors ->
                    if isEnum constructors then
                        constructors
                            |>  Dict.keys

                    else
                        []

                _ ->
                    []

        _ ->
            []

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


asAlias : Type.Definition ta -> Maybe FQName
asAlias typeDef =
     case typeDef of
        -- This is a type alias, so we want to get that as a type and register the base type as well.
        Type.TypeAliasDefinition _ (Type.Reference _ aliasFQN _) ->
            Just aliasFQN

        _ -> Nothing
