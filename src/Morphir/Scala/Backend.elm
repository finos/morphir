{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}


module Morphir.Scala.Backend exposing
    ( mapDistribution
    , Options
    )

{-| This module encapsulates the Scala backend. It takes the Morphir IR as the input and returns an in-memory
representation of files generated. The consumer is responsible for getting the input IR and saving the output
to the file-system.

@docs mapDistribution


# Options

@docs Options

-}

import Dict
import List
import Morphir.File.FileMap exposing (FileMap)
import Morphir.File.SourceCode exposing (Doc)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Package as Package
import Morphir.IR.Type exposing (Type)
import Morphir.Scala.Feature.Codec exposing (mapModuleDefinitionToCodecs)
import Morphir.Scala.Feature.Core exposing (mapModuleDefinition)
import Morphir.Scala.PrettyPrinter as PrettyPrinter
import Set exposing (Set)


{-| Placeholder for code generator options. Currently empty.
-}
type alias Options =
    { limitToModules : Maybe (Set ModuleName)
    , includeCodecs : Bool
    }


{-| Entry point for the Scala backend. It takes the Morphir IR as the input and returns an in-memory
representation of files generated.
-}
mapDistribution : Options -> Distribution -> FileMap
mapDistribution opt distro =
    case distro of
        Distribution.Library packageName dependencies packageDef ->
            case opt.limitToModules of
                Just modulesToInclude ->
                    mapPackageDefinition opt distro packageName (Package.selectModules modulesToInclude packageName packageDef)

                Nothing ->
                    mapPackageDefinition opt distro packageName packageDef


mapPackageDefinition : Options -> Distribution -> Package.PackageName -> Package.Definition ta (Type ()) -> FileMap
mapPackageDefinition opt distribution packagePath packageDef =
    packageDef.modules
        |> Dict.toList
        |> List.concatMap
            (\( modulePath, moduleImpl ) ->
                List.concat
                    [ mapModuleDefinition packagePath modulePath moduleImpl
                    , if opt.includeCodecs then
                        mapModuleDefinitionToCodecs packagePath modulePath moduleImpl

                      else
                        []
                    ]
            )
        |> List.map
            (\compilationUnit ->
                let
                    fileContent : Doc
                    fileContent =
                        compilationUnit
                            |> PrettyPrinter.mapCompilationUnit (PrettyPrinter.Options 2 80)
                in
                ( ( compilationUnit.dirPath, compilationUnit.fileName ), fileContent )
            )
        |> Dict.fromList
