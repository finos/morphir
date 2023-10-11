module Morphir.Snowpark.Backend exposing (..)

import Dict
import List
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.Distribution as Distribution exposing (..)
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package
import Morphir.IR.Path exposing (Path)
import Morphir.IR.Type exposing (Type)
import Morphir.Scala.AST as Scala
import Morphir.Scala.PrettyPrinter as PrettyPrinter
import Morphir.TypeSpec.Backend exposing (mapModuleDefinition)

type alias Options =
    {}

mapDistribution : Options -> Distribution -> FileMap
mapDistribution _ distro =
    case distro of
        Distribution.Library packageName _ packageDef ->
            mapPackageDefinition distro packageName packageDef


mapPackageDefinition : Distribution -> Package.PackageName -> Package.Definition ta (Type ()) -> FileMap
mapPackageDefinition _ packagePath packageDef =
    let
        generatedScala =
            packageDef.modules
                |> Dict.toList
                |> List.concatMap
                    (\( modulePath, _ ) ->
                        mapModuleDefinition packagePath modulePath
                    )
    in
    generatedScala
        |> List.map
            (\compilationUnit ->
                let
                    fileContent =
                        compilationUnit
                            |> PrettyPrinter.mapCompilationUnit (PrettyPrinter.Options 2 80)
                in
                ( ( compilationUnit.dirPath, compilationUnit.fileName ), fileContent )
            )
        |> Dict.fromList


mapModuleDefinition : Package.PackageName -> Path -> List Scala.CompilationUnit
mapModuleDefinition currentPackagePath currentModulePath =
    let
        ( scalaPackagePath, moduleName ) =
            case currentModulePath |> List.reverse of
                [] ->
                    ( [], [] )

                lastName :: reverseModulePath ->
                    let
                        parts =
                            List.append currentPackagePath (List.reverse reverseModulePath)
                    in
                    ( parts |> (List.concat >> List.map String.toLower), lastName )

        moduleUnit : Scala.CompilationUnit
        moduleUnit =
            { dirPath = scalaPackagePath
            , fileName = (moduleName |> Name.toTitleCase) ++ ".scala"
            , packageDecl = scalaPackagePath
            , imports = []
            , typeDecls = []
            }
    in
    [ moduleUnit ]
