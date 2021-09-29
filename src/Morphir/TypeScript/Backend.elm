module Morphir.TypeScript.Backend exposing
    ( Options
    , mapDistribution
    , mapTypeDefinition
    )

{-| This module contains the TypeScript backend that translates the Morphir IR into TypeScript.
-}

import Dict
import Morphir.File.FileMap exposing (FileMap)
import Morphir.File.SourceCode exposing (newLine)
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.TypeScript.AST as TS exposing (namespacePath)
import Morphir.TypeScript.NamespaceMerger exposing (mergeNamespaces)
import Morphir.TypeScript.PrettyPrinter as PrettyPrinter exposing (getTypeScriptPackagePathAndModuleName)


standardPrettyPrinterOptions : PrettyPrinter.Options
standardPrettyPrinterOptions =
    { indentDepth = 2 }


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
    let
        compilationUnitToFileMapElement : TS.CompilationUnit -> ( ( List String, String ), String )
        compilationUnitToFileMapElement compilationUnit =
            let
                fileContent =
                    compilationUnit
                        |> PrettyPrinter.mapCompilationUnit standardPrettyPrinterOptions
            in
            ( ( compilationUnit.dirPath, compilationUnit.fileName ), fileContent )

        individualModuleFiles : List ( ( List String, String ), String )
        individualModuleFiles =
            packageDef.modules
                |> Dict.toList
                |> List.concatMap
                    (\( modulePath, moduleImpl ) ->
                        mapModuleDefinition opt distribution packagePath modulePath moduleImpl
                            |> List.map compilationUnitToFileMapElement
                    )

        topLevelPackageName : String
        topLevelPackageName =
            case packagePath of
                firstName :: _ ->
                    (firstName |> Name.toTitleCase) ++ ".ts"

                _ ->
                    ".ts"

        topLevelCompilationUnit : TS.CompilationUnit
        topLevelCompilationUnit =
            { dirPath = []
            , fileName = topLevelPackageName
            , packagePath = []
            , modulePath = []
            , typeDefs = mapModuleNamespacesForTopLevelFile packagePath packageDef
            }

        topLevelNameSpaceModuleFile : List ( ( List String, String ), String )
        topLevelNameSpaceModuleFile =
            [ compilationUnitToFileMapElement topLevelCompilationUnit ]
    in
    (individualModuleFiles ++ topLevelNameSpaceModuleFile)
        |> Dict.fromList


mapModuleNamespacesForTopLevelFile : Package.PackageName -> Package.Definition ta (Type ()) -> List TS.TypeDef
mapModuleNamespacesForTopLevelFile packagePath packageDef =
    packageDef.modules
        |> Dict.toList
        |> List.map
            (\( modulePath, moduleImpl ) ->
                ( moduleImpl.access |> mapPrivacy
                , TS.namespacePath packagePath modulePath
                )
            )
        |> List.concatMap
            (\( privacy, namespacePath ) ->
                case namespacePath.packagePath ++ namespacePath.modulePath |> List.reverse of
                    [] ->
                        []

                    lastName :: restOfPath ->
                        let
                            importStatement =
                                TS.ImportStatement
                                    { name = lastName
                                    , privacy = privacy
                                    , typeExpression = TS.NamespaceRef namespacePath
                                    }

                            step : Name -> TS.TypeDef -> TS.TypeDef
                            step name state =
                                TS.Namespace
                                    { name = name
                                    , privacy = privacy
                                    , content = List.singleton state
                                    }
                        in
                        [ List.foldl step importStatement restOfPath ]
            )
        |> mergeNamespaces


mapModuleDefinition : Options -> Distribution -> Package.PackageName -> Path -> AccessControlled (Module.Definition ta (Type ())) -> List TS.CompilationUnit
mapModuleDefinition opt distribution currentPackagePath currentModulePath accessControlledModuleDef =
    let
        ( typeScriptPackagePath, moduleName ) =
            getTypeScriptPackagePathAndModuleName currentPackagePath currentModulePath

        typeDefs : List TS.TypeDef
        typeDefs =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.concatMap
                    (\( typeName, typeDef ) -> mapTypeDefinition typeName typeDef)

        namespace : TS.TypeDef
        namespace =
            TS.Namespace
                { name =
                    (currentPackagePath ++ currentModulePath)
                        |> Path.toString Name.toTitleCase "_"
                        |> List.singleton
                , privacy = TS.Public
                , content = typeDefs
                }

        moduleUnit : TS.CompilationUnit
        moduleUnit =
            { dirPath = typeScriptPackagePath
            , fileName = (moduleName |> Name.toTitleCase) ++ ".ts"
            , packagePath = currentPackagePath
            , modulePath = currentModulePath
            , typeDefs = List.singleton namespace
            }
    in
    [ moduleUnit ]


{-| Map a Morphir Constructor (A tuple of Name and Constructor Args) to a Typescript AST Interface
-}
mapConstructor : TS.Privacy -> List TS.TypeExp -> ( Name, List ( Name, Type.Type ta ) ) -> TS.TypeDef
mapConstructor privacy variables ( ctorName, ctorArgs ) =
    let
        kindField =
            ( "kind", TS.LiteralString (ctorName |> Name.toTitleCase) )

        otherFields =
            ctorArgs
                |> List.map
                    (\( argName, argType ) ->
                        ( argName |> Name.toCamelCase, mapTypeExp argType )
                    )
    in
    TS.Interface
        { name = ctorName
        , privacy = privacy
        , variables = variables
        , fields = kindField :: otherFields
        }


{-| Map a Morphir type definition into a list of TypeScript type definitions. The reason for returning a list is that
some Morphir type definitions can only be represented by a combination of multiple type definitions in TypeScript.
-}
mapTypeDefinition : Name -> AccessControlled (Documented (Type.Definition ta)) -> List TS.TypeDef
mapTypeDefinition name typeDef =
    let
        doc =
            typeDef.value.doc

        privacy =
            typeDef.access |> mapPrivacy
    in
    case typeDef.value.value of
        Type.TypeAliasDefinition variables typeExp ->
            [ TS.TypeAlias
                { name = name
                , privacy = privacy
                , doc = doc
                , variables = variables |> List.map Name.toCamelCase |> List.map (\var -> TS.Variable var)
                , typeExpression = typeExp |> mapTypeExp
                }
            ]

        Type.CustomTypeDefinition variables accessControlledConstructors ->
            let
                tsVariables =
                    variables |> List.map Name.toCamelCase |> List.map (\var -> TS.Variable var)

                constructors =
                    accessControlledConstructors.value
                        |> Dict.toList

                constructorNames =
                    accessControlledConstructors.value
                        |> Dict.keys

                constructorInterfaces =
                    constructors
                        |> List.map (mapConstructor privacy tsVariables)

                union =
                    if List.all ((==) name) constructorNames then
                        []

                    else
                        List.singleton
                            (TS.TypeAlias
                                { name = name
                                , privacy = privacy
                                , doc = doc
                                , variables = tsVariables
                                , typeExpression =
                                    TS.Union
                                        (constructors
                                            |> List.map
                                                (\( ctorName, _ ) ->
                                                    TS.TypeRef (FQName.fQName [] [] ctorName) tsVariables
                                                )
                                        )
                                }
                            )
            in
            union ++ constructorInterfaces


{-| Map a Morphir type expression into a TypeScript type expression.
-}
mapTypeExp : Type.Type ta -> TS.TypeExp
mapTypeExp tpe =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "bool" ] ) [] ->
            TS.Boolean

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "dict" ] ], [ "dict" ] ) [ dictKeyType, dictValType ] ->
            TS.List (TS.Tuple [ mapTypeExp dictKeyType, mapTypeExp dictValType ])

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) [ listType ] ->
            TS.List (mapTypeExp listType)

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] ->
            TS.Number

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) [] ->
            TS.Number

        Type.Record _ fieldList ->
            TS.Object
                (fieldList
                    |> List.map
                        (\field ->
                            ( field.name |> Name.toTitleCase, mapTypeExp field.tpe )
                        )
                )

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "char" ] ], [ "char" ] ) [] ->
            TS.String

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) [] ->
            TS.String

        Type.Tuple _ tupleTypesList ->
            TS.Tuple (List.map mapTypeExp tupleTypesList)

        Type.Reference _ fQName typeList ->
            TS.TypeRef fQName (typeList |> List.map mapTypeExp)

        Type.Unit _ ->
            TS.Tuple []

        Type.Variable _ name ->
            TS.Variable (Name.toCamelCase name)

        Type.ExtensibleRecord a argName fields ->
            TS.UnhandledType "ExtensibleRecord"

        Type.Function a argType returnType ->
            TS.UnhandledType "Function"


{-| Utility funciton: map an AccessControlled.Access object, to a TS.Privacy Object
-}
mapPrivacy : Access -> TS.Privacy
mapPrivacy privacy =
    case privacy of
        Public ->
            TS.Public

        Private ->
            TS.Private
