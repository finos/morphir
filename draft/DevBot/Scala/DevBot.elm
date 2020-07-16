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
