module Morphir.Metadata exposing
    ( BaseTypes, EnumExtensionComponent, Enums, Modules, Types, Aliases, Metadata, UnionTypes
    , mapDistribution
    , getTypes, getEnums, getBaseTypes, getAliases, getDocumentation, getModules, getEnumsWithExtensions, enumExtensionName, getUnions, isEnumExtension
    )

{-| The Metadata module analyses a distribution for the type of metadata information that would be helpful in
automating things like data dictionaries, lineage tracking, and the such.


# Types

@docs BaseTypes, EnumExtensionComponent, Enums, Modules, Types, Aliases, Metadata, UnionTypes


# Processing

@docs mapDistribution


# Utilities

@docs getTypes, getEnums, getBaseTypes, getAliases, getDocumentation, getModules, getEnumsWithExtensions, enumExtensionName, getUnions, isEnumExtension

-}

import Dict exposing (Dict)
import Html exposing (table)
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled, withPublicAccess)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Type as Type exposing (Constructors, Specification(..), Type(..))
import Morphir.Scala.AST exposing (Documented)


{-| Structure for holding metadata information from processing the distribution.
-}
type Metadata ta
    = Metadata Modules (Types ta) Enums BaseTypes (UnionTypes ta) Aliases


{-| The registry of modules through entire distribution.
-}
type alias Modules =
    List ModuleName


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
A base type is any union type that has only one single-argument option.
-}
type alias BaseTypes =
    Dict FQName FQName


{-| The registry of union types through the entire distribution.
A union type is any ADT that has more than one single-argument option.
-}
type alias UnionTypes ta =
    Dict FQName (Documented (Type.Definition ta))


{-| The registry of aliases through the entire distribution.
An alias is any type alias that aliases a non-record type.
-}
type alias Aliases =
    Dict FQName FQName


{-| An enum extension is a special pattern of union type that is either an enum or a name with no arguments
-}
type EnumExtensionComponent
    = ExtensionBase ( FQName, List Name )
    | ExtensionValue Name


{-| Access function for getting the module registry from a Metadata structure.
-}
getModules : Metadata ta -> Modules
getModules meta =
    case meta of
        Metadata modules _ _ _ _ _ ->
            modules


{-| Access function for getting the type registry from a Metadata structure.
-}
getTypes : Metadata ta -> Types ta
getTypes meta =
    case meta of
        Metadata _ types _ _ _ _ ->
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
        Metadata _ _ enums _ _ _ ->
            enums


{-| Access function for getting the enum registry from a Metadata structure that includes EnumExtensions.
-}
getEnumsWithExtensions : Metadata ta -> Enums
getEnumsWithExtensions meta =
    let
        enums =
            getEnums meta

        enumExtensions =
            getEnumExtensions meta
                |> Dict.toList
                |> List.map extensionToEnum
                |> Dict.fromList
    in
    Dict.union enums enumExtensions


{-| Access function for getting the base type registry from a Metadata structure.
-}
getBaseTypes : Metadata ta -> BaseTypes
getBaseTypes meta =
    case meta of
        Metadata _ _ _ baseTypes _ _ ->
            baseTypes


{-| Access function for getting the union type registry from a Metadata structure.
-}
getUnions : Metadata ta -> UnionTypes ta
getUnions meta =
    case meta of
        Metadata _ _ _ _ unions _ ->
            unions


{-| Access function for getting the alias type registry from a Metadata structure.
-}
getAliases : Metadata ta -> Aliases
getAliases meta =
    case meta of
        Metadata _ _ _ _ _ aliases ->
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
        modules =
            packageDef.modules
                |> Dict.keys

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

        unions =
            typeList
                |> List.filter
                    (\( k, v ) ->
                        isUnion v.value
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
    Metadata modules types enums bases unions aliases


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


{-| Decides whether a union type is an enum by ensuring it only has constructors with base type enum or no arg constructors.
-}
isEnumExtension : Metadata a -> Constructors a -> Bool
isEnumExtension metadata constructors =
    let
        ( totalEmpties, totalEnums, totalOthers ) =
            constructors
                |> Dict.values
                |> List.foldl
                    (\args ( empties, enums, others ) ->
                        case args of
                            [] ->
                                ( empties + 1, enums, others )

                            [ ( _, Type.Reference _ fqn _ ) ] ->
                                getEnums metadata
                                    |> Dict.get fqn
                                    |> Maybe.map (\x -> ( empties, enums + 1, others ))
                                    |> Maybe.withDefault ( empties, enums, others + 1 )

                            _ ->
                                ( empties, enums, others + 1 )
                    )
                    ( 0, 0, 0 )
    in
    totalEmpties > 0 && totalEnums > 0 && totalOthers == 0


asEnumExtension : Metadata ta -> Type.Definition ta -> List EnumExtensionComponent
asEnumExtension metadata typeDef =
    case typeDef of
        Type.CustomTypeDefinition _ accessControlledCtors ->
            case accessControlledCtors |> withPublicAccess of
                Just constructors ->
                    if isEnumExtension metadata constructors then
                        constructors
                            |> Dict.toList
                            |> List.filterMap
                                (\( name, constructor ) ->
                                    case constructor of
                                        [] ->
                                            Just (ExtensionValue name)

                                        [ ( _, Type.Reference _ baseFqn _ ) ] ->
                                            getEnums metadata
                                                |> Dict.get baseFqn
                                                |> Maybe.map (\names -> ExtensionBase ( baseFqn, names ))

                                        _ ->
                                            Nothing
                                )

                    else
                        []

                _ ->
                    []

        _ ->
            []


getEnumExtensions : Metadata a -> Dict FQName (List EnumExtensionComponent)
getEnumExtensions metadata =
    let
        xs =
            getTypes metadata
                |> Dict.toList
                |> List.filterMap
                    (\( fqn, value ) ->
                        let
                            extensions =
                                asEnumExtension metadata value.value
                        in
                        if List.isEmpty extensions then
                            Nothing

                        else
                            Just ( fqn, extensions )
                    )
    in
    Dict.fromList xs


extensionToEnum : ( FQName, List EnumExtensionComponent ) -> ( FQName, List Name )
extensionToEnum ( fqn, components ) =
    ( fqn, List.concatMap enumExtensionName components )


{-| Extract the names out of an enum extension.
-}
enumExtensionName : EnumExtensionComponent -> List Name
enumExtensionName ee =
    case ee of
        ExtensionBase ( _, names ) ->
            names

        ExtensionValue name ->
            [ name ]


{-| Decides whether a type is a base type (one single argument constructor) through Maybe.
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
                -- One single argument
                [ [ ( _, Type.Reference _ fqn _ ) ] ] ->
                    Just fqn

                _ ->
                    Nothing

        _ ->
            Nothing


{-| Decides whether a type is a base type through Maybe.
-}
isUnion : Type.Definition ta -> Bool
isUnion typeDef =
    case typeDef of
        Type.CustomTypeDefinition _ accessControlledCtors ->
            let
                values =
                    accessControlledCtors
                        |> withPublicAccess
                        |> Maybe.map Dict.values
                        |> Maybe.withDefault []
            in
            List.length values > 1

        _ ->
            False


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
