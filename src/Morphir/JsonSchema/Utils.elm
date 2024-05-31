module Morphir.JsonSchema.Utils exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)


type alias QualifiedName =
    ( Path, Name )


{-|

    This function extracts ALL the type definitions from a module.
    If any type is a reference type, it would search the package to collect all the referenced types

-}
extractTypes : ModuleName -> Module.Definition () (Type ()) -> PackageName -> Package.Definition () (Type ()) -> List ( QualifiedName, Type.Definition () )
extractTypes modName moduleDef pkgName pkgDef =
    moduleDef.types
        |> Dict.toList
        |> List.concatMap
            (\( name, accessControlled ) ->
                case accessControlled.value.value of
                    Type.TypeAliasDefinition _ typ ->
                        case typ of
                            Type.Reference () ( _, _, _ ) [] ->
                                ( ( modName, name ), accessControlled.value.value )
                                    :: getTypeDefinitionsFromModule name modName (Just moduleDef) pkgName pkgDef

                            _ ->
                                [ ( ( modName, name ), accessControlled.value.value ) ]

                    Type.CustomTypeDefinition typName ctors ->
                        let
                            typeDefs =
                                [ ( ( modName, name ), accessControlled.value.value ) ]
                                    :: (ctors.value
                                            |> Dict.toList
                                            |> List.map
                                                (\( ctorName, ctorArgs ) ->
                                                    ctorArgs
                                                        |> List.concatMap
                                                            (\( argName, argType ) ->
                                                                case argType of
                                                                    Type.Reference () ( p, m, l ) [] ->
                                                                        getTypeDefinitionsFromModule name modName (Just moduleDef) pkgName pkgDef

                                                                    _ ->
                                                                        []
                                                            )
                                                )
                                       )
                        in
                        typeDefs |> List.concat
            )


{-|

    This function searches through a module to find ONE type definition.
    If the type is a reference, it searches the package and recursively collect all the referenced types

-}
getTypeDefinitionsFromModule : Name -> ModuleName -> Maybe (Module.Definition () (Type ())) -> PackageName -> Package.Definition () (Type ()) -> List ( QualifiedName, Type.Definition () )
getTypeDefinitionsFromModule typeName moduleName moduleDef pkgName pkgDef =
    let
        typeDefList =
            case moduleDef of
                Just moduleDefn ->
                    moduleDefn.types
                        |> Dict.toList
                        |> List.map
                            (\( name, accControlled ) ->
                                case accControlled.value.value of
                                    Type.TypeAliasDefinition _ typ ->
                                        let
                                            nameBeingProcessed =
                                                name |> Name.toTitleCase

                                            nameBeingSearched =
                                                typeName |> Name.toTitleCase
                                        in
                                        if nameBeingSearched == nameBeingProcessed then
                                            case typ of
                                                Type.Reference () ( _, m, l ) [] ->
                                                    let
                                                        refModuleDef =
                                                            Package.lookupModuleDefinition m pkgDef

                                                        refTypeDef =
                                                            getTypeDefinitionsFromModule l m refModuleDef pkgName pkgDef

                                                        baseTypeDef =
                                                            ( ( moduleName, typeName ), accControlled.value.value )
                                                    in
                                                    baseTypeDef :: refTypeDef

                                                _ ->
                                                    [ ( ( moduleName, typeName ), accControlled.value.value ) ]

                                        else
                                            []

                                    Type.CustomTypeDefinition _ ctors ->
                                        let
                                            nameBeingProcessed =
                                                name |> Name.toTitleCase

                                            nameBeingSearched =
                                                typeName |> Name.toTitleCase
                                        in
                                        if nameBeingSearched == nameBeingProcessed then
                                            let
                                                -- we must map  the ctor args to see if any of them is has a Reference type
                                                refTypesDefs =
                                                    [ ( ( moduleName, typeName ), accControlled.value.value ) ]
                                                        :: (ctors.value
                                                                |> Dict.toList
                                                                |> List.concatMap
                                                                    (\( _, ctorArgs ) ->
                                                                        ctorArgs
                                                                            |> List.map
                                                                                (\( _, argType ) ->
                                                                                    case argType of
                                                                                        Type.Reference _ ( _, m, l ) [] ->
                                                                                            let
                                                                                                refModuleDef =
                                                                                                    Package.lookupModuleDefinition m pkgDef

                                                                                                refTypeDef =
                                                                                                    getTypeDefinitionsFromModule l m refModuleDef pkgName pkgDef

                                                                                                baseTypeDef =
                                                                                                    ( ( moduleName, typeName ), accControlled.value.value )
                                                                                            in
                                                                                            baseTypeDef :: refTypeDef

                                                                                        _ ->
                                                                                            []
                                                                                )
                                                                    )
                                                           )
                                            in
                                            ( ( moduleName, typeName ), accControlled.value.value ) :: (refTypesDefs |> List.concat)

                                        else
                                            []
                            )

                Nothing ->
                    []
    in
    typeDefList |> List.concat
