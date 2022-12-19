module Morphir.JsonSchema.Utils exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)


type alias QualifiedName =
    ( Path, Name )


extractTypes : ModuleName -> Module.Definition () (Type ()) -> List ( QualifiedName, Type.Definition () )
extractTypes modName definition =
    definition.types
        |> Dict.toList
        |> List.map
            (\( name, accessControlled ) ->
                ( ( modName, name ), accessControlled.value.value )
            )


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
                                        if typeName == name then
                                            let
                                                -- we must map  the ctor args to see if any of them is has a Reference type
                                                refTypesDefs =
                                                    ctors.value
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
                                                                                            ( ( m, l ), accControlled.value.value )
                                                                                    in
                                                                                    baseTypeDef :: refTypeDef

                                                                                _ ->
                                                                                    []
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
