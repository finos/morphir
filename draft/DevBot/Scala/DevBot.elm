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


module SlateX.DevBot.Scala.DevBot exposing (..)


import Dict
import SlateX.AST.Package exposing (Package)
import SlateX.FileSystem exposing (FileMap)
import SlateX.DevBot.Scala.SlateXToSlateX.SlateXToSlateX as SlateXToSlateX
import SlateX.DevBot.Scala.SlateXToScala.Modules as SlateXToScala
import SlateX.DevBot.Scala.ScalaToScala.ManageImports as ScalaToScala
import SlateX.DevBot.Scala.ScalaToDoc.ScalaToDoc as ScalaToDoc


mapPackage : Package -> FileMap
mapPackage package =
    package
        |> SlateXToSlateX.mapPackage
        |> .implementation
        |> Dict.toList
        |> List.concatMap
            (\( modulePath, moduleImpl ) ->
                SlateXToScala.mapImplementation package modulePath moduleImpl
                    |> List.map
                        (\compilationUnit ->
                            let
                                opt =
                                    ScalaToDoc.Options 2 80

                                fileContent =
                                    compilationUnit
                                        |> ScalaToScala.mapCompilationUnit
                                        |> ScalaToDoc.mapCompilationUnit opt
                            in
                            ( ( compilationUnit.dirPath, compilationUnit.fileName ), fileContent )
                        )
            )
        |> Dict.fromList    
