module Morphir.TypeScript.Backend exposing
    ( Options
    , mapDistribution
    )

{-| This module contains the TypeScript backend that translates the Morphir IR into TypeScript.
-}

import Dict
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type exposing (Type)
import Morphir.TypeScript.AST as TS
import Morphir.TypeScript.Backend.Imports exposing (getTypeScriptPackagePathAndModuleName, getUniqueImportRefs, makeRelativeImport, renderInternalImport)
import Morphir.TypeScript.Backend.TopLevelNamespace exposing (makeTopLevelNamespaceModule)
import Morphir.TypeScript.Backend.Types exposing (mapTypeDefinition)
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


{-| Represents one element of a FileMap,
ie the file path and the contents of file that needs to be created in the backend output.
The structure is ( (directoryPath, Filename), fileContent)
-}
type alias FileMapElement =
    ( ( List String, String ), String )


mapPackageDefinition : Options -> Distribution -> Package.PackageName -> Package.Definition ta (Type ()) -> FileMap
mapPackageDefinition opt distribution packagePath packageDef =
    let
        topLevelNamespaceModule : TS.CompilationUnit
        topLevelNamespaceModule =
            makeTopLevelNamespaceModule packagePath packageDef

        individualModules : List TS.CompilationUnit
        individualModules =
            packageDef.modules
                |> Dict.toList
                |> List.concatMap
                    (\( modulePath, moduleImpl ) ->
                        mapModuleDefinition opt distribution packagePath modulePath moduleImpl
                    )

        compilationUnitToFileMapElement : TS.CompilationUnit -> FileMapElement
        compilationUnitToFileMapElement compilationUnit =
            let
                fileContent =
                    compilationUnit
                        |> PrettyPrinter.mapCompilationUnit
            in
            ( ( compilationUnit.dirPath, compilationUnit.fileName ), fileContent )
    in
    (topLevelNamespaceModule :: individualModules)
        |> List.map compilationUnitToFileMapElement
        |> Dict.fromList


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
                { name = TS.namespaceNameFromPackageAndModule currentPackagePath currentModulePath
                , privacy = TS.Public
                , content = typeDefs
                }

        codecsImport =
            { importClause = "* as codecs"
            , moduleSpecifier = makeRelativeImport typeScriptPackagePath "morphir/internal/Codecs"
            }

        imports =
            codecsImport
                :: (namespace
                        |> getUniqueImportRefs currentPackagePath currentModulePath
                        |> List.map (renderInternalImport typeScriptPackagePath)
                   )

        {--Collect references from inside the module,
        filter out references to current module
        then sort references and get a list of unique references-}
        moduleUnit : TS.CompilationUnit
        moduleUnit =
            { dirPath = typeScriptPackagePath
            , fileName = (moduleName |> Name.toTitleCase) ++ ".ts"
            , imports = imports
            , typeDefs = List.singleton namespace
            }
    in
    [ moduleUnit ]
