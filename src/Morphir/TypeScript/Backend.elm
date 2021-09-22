module Morphir.TypeScript.Backend exposing
    ( Options
    , mapDistribution
    , mapTypeDefinition
    )

{-| This module contains the TypeScript backend that translates the Morphir IR into TypeScript.
-}

import Dict
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.TypeScript.AST as TS
import Morphir.TypeScript.PrettyPrinter as PrettyPrinter


{-| Placeholder for code generator options. Currently empty.
-}
type alias Options =
    {}


{-| Entry point for the TypeScript backend. It takes the Morphir IR as the input and returns an in-memory
representation of files generated.
-}
mapDistribution : Options -> Distribution -> FileMap
mapDistribution opt distro =
    case distro of
        Distribution.Library packagePath dependencies packageDef ->
            mapPackageDefinition opt distro packagePath packageDef


mapPackageDefinition : Options -> Distribution -> Package.PackageName -> Package.Definition ta (Type ()) -> FileMap
mapPackageDefinition opt distribution packagePath packageDef =
    packageDef.modules
        |> Dict.toList
        |> List.concatMap
            (\( modulePath, moduleImpl ) ->
                mapModuleDefinition opt distribution packagePath modulePath moduleImpl
                    |> List.map
                        (\compilationUnit ->
                            let
                                fileContent =
                                    compilationUnit
                                        |> PrettyPrinter.mapCompilationUnit (PrettyPrinter.Options 2)
                            in
                            ( ( compilationUnit.dirPath, compilationUnit.fileName ), fileContent )
                        )
            )
        |> Dict.fromList


mapModuleDefinition : Options -> Distribution -> Package.PackageName -> Path -> AccessControlled (Module.Definition ta (Type ())) -> List TS.CompilationUnit
mapModuleDefinition opt distribution currentPackagePath currentModulePath accessControlledModuleDef =
    let
        ( typeScriptPackagePath, moduleName ) =
            case currentModulePath |> List.reverse of
                [] ->
                    ( [], [] )

                lastName :: reverseModulePath ->
                    ( List.append (currentPackagePath |> List.map (Name.toCamelCase >> String.toLower)) (reverseModulePath |> List.reverse |> List.map (Name.toCamelCase >> String.toLower)), lastName )

        typeDefs : List TS.TypeDef
        typeDefs =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.concatMap
                    (\( typeName, typeDef ) -> mapTypeDefinition typeName typeDef)

        moduleUnit : TS.CompilationUnit
        moduleUnit =
            { dirPath = typeScriptPackagePath
            , fileName = (moduleName |> Name.toTitleCase) ++ ".ts"
            , typeDefs = typeDefs
            }
    in
    [ moduleUnit ]


{-| Map a Morphir type definition into a list of TypeScript type definitions. The reason for returning a list is that
some Morphir type definitions can only be represented by a combination of multiple type definitions in TypeScript.
-}
mapTypeDefinition : Name -> AccessControlled (Documented (Type.Definition ta)) -> List TS.TypeDef
mapTypeDefinition name typeDef =
    case typeDef.value.value of
        Type.TypeAliasDefinition typeArgs typeExp ->
            [ TS.TypeAlias
                (name |> Name.toTitleCase)
                (typeExp |> mapTypeExp)
            ]

        Type.CustomTypeDefinition typeArgs accessControlledConstructors ->
            let
                constructors =
                    accessControlledConstructors.value
                        |> Dict.toList

                constructorInterfaces =
                    constructors
                        |> List.map
                            (\( ctorName, ctorArgs ) ->
                                TS.Interface
                                    (ctorName |> Name.toTitleCase)
                                    (ctorArgs
                                        |> List.map
                                            (\( argName, argType ) ->
                                                ( argName |> Name.toCamelCase, mapTypeExp argType )
                                            )
                                    )
                            )

                union =
                    TS.TypeAlias
                        (name |> Name.toTitleCase)
                        (TS.Union
                            (constructors
                                |> List.map
                                    (\( ctorName, _ ) ->
                                        TS.TypeRef (ctorName |> Name.toTitleCase)
                                    )
                            )
                        )
            in
            constructorInterfaces ++ [ union ]


{-| Map a Morphir type expression into a TypeScript type expression.
-}
mapTypeExp : Type.Type ta -> TS.TypeExp
mapTypeExp tpe =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) [] ->
            TS.String

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) [] ->
            TS.Number

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] ->
            TS.Number

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "bool" ] ) [] ->
            TS.Boolean

        Type.Reference _ ( packageName, moduleName, localName ) [] ->
            TS.TypeRef (localName |> Name.toTitleCase)

        Type.Reference _ fqName _ ->
            TS.UnhandledType ("Reference " ++ FQName.toString fqName ++ ")")

        Type.Variable a name ->
            TS.UnhandledType ("Variable (" ++ Name.toCamelCase name ++ ")")

        Type.Tuple a elemTypes ->
            TS.UnhandledType "Tuple"

        Type.Record a fields ->
            TS.UnhandledType "Record"

        Type.ExtensibleRecord a argName fields ->
            TS.UnhandledType "ExtensibleRecord"

        Type.Function a argType returnType ->
            TS.UnhandledType "Function"

        Type.Unit a ->
            TS.UnhandledType "Unit"
