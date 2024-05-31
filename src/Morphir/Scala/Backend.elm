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
    , Error(..)
    )

{-| This module encapsulates the Scala backend. It takes the Morphir IR as the input and returns an in-memory
representation of files generated. The consumer is responsible for getting the input IR and saving the output
to the file-system.

@docs mapDistribution


# Options

@docs Options
@docs Error

-}

import Dict
import List
import Morphir.Correctness.Test exposing (TestSuite)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.File.SourceCode exposing (Doc)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Package as Package
import Morphir.IR.Type exposing (Type)
import Morphir.SDK.ResultList as ResultList
import Morphir.Scala.Feature.Codec as Codec exposing (mapModuleDefinitionToCodecs)
import Morphir.Scala.Feature.Core exposing (mapModuleDefinition)
import Morphir.Scala.Feature.TestBackend as TestBackend
import Morphir.Scala.PrettyPrinter as PrettyPrinter
import Set exposing (Set)


{-| Placeholder for code generator options.
-}
type alias Options =
    { limitToModules : Maybe (Set ModuleName)
    , includeCodecs : Bool
    , testOptions : TestBackend.Options
    }


{-| Possible errors during code generation.
-}
type Error
    = TestError TestBackend.Errors
    | CodecError Codec.Error


{-| Entry point for the Scala backend. It takes the Morphir IR as the input and returns an in-memory
representation of files generated.
-}
mapDistribution : Options -> TestSuite -> Distribution -> Result Error FileMap
mapDistribution opt testSuite distro =
    case distro of
        Distribution.Library packageName dependencies packageDef ->
            case opt.limitToModules of
                Just modulesToInclude ->
                    mapPackageDefinition opt testSuite distro packageName (Package.selectModules modulesToInclude packageName packageDef)

                Nothing ->
                    mapPackageDefinition opt testSuite distro packageName packageDef


mapPackageDefinition : Options -> TestSuite -> Distribution -> Package.PackageName -> Package.Definition ta (Type ()) -> Result Error FileMap
mapPackageDefinition opt testSuite distribution packagePath packageDef =
    let
        generatedTestsResult =
            testSuite
                |> TestBackend.genTestSuite opt.testOptions packagePath distribution
                |> Result.mapError TestError

        generatedScala =
            packageDef.modules
                |> Dict.toList
                |> List.concatMap
                    (\( modulePath, moduleImpl ) ->
                        List.concat
                            [ mapModuleDefinition packagePath modulePath moduleImpl
                            ]
                    )

        generatedCodecsResult =
            if opt.includeCodecs then
                packageDef.modules
                    |> Dict.toList
                    |> List.map
                        (\( modulePath, moduleImpl ) ->
                            mapModuleDefinitionToCodecs packagePath modulePath moduleImpl
                                |> Result.map (List.singleton >> List.concat)
                        )
                    |> ResultList.keepFirstError
                    |> Result.map List.concat
                    |> Result.mapError CodecError

            else
                Ok []
    in
    Result.map2
        (\generatedTests generatedCodecs ->
            [ generatedScala, generatedCodecs, generatedTests ]
                |> List.concat
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
        )
        generatedTestsResult
        generatedCodecsResult
