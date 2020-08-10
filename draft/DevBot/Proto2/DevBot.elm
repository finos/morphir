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


module SlateX.DevBot.Proto2.DevBot exposing (..)


import Dict
import SlateX.AST.Package exposing (Package)
import SlateX.FileSystem exposing (FileMap)
import SlateX.DevBot.Proto2.SlateXToProto2.Modules as Modules
import SlateX.DevBot.Proto2.Proto2ToDoc.Proto2ToDoc as Proto2ToDoc
import SlateX.Mapping.Naming as Naming


mapPackage : Package -> FileMap
mapPackage package =
    package.interface
        |> Dict.toList
        |> List.concatMap
            (\( modulePath, moduleInt ) ->
                Modules.mapInterface package modulePath moduleInt
                    |> List.map 
                        (\protoFile ->
                            ( modulePath, protoFile )
                        )    
            )
        |> List.filterMap
            (\( modulePath, protoFile ) ->
                case List.reverse modulePath of
                    [] ->
                        Nothing

                    localName :: modulePathReversed ->
                        let
                            dirPath = 
                                modulePathReversed 
                                    |> List.reverse 
                                    |> List.map Naming.toTitleCase

                            opt =
                                Proto2ToDoc.Options 2 80

                            content =
                                protoFile
                                    |> Proto2ToDoc.mapProtoFile opt
                        in
                        Just 
                            ( ( dirPath, Naming.toTitleCase localName ++ ".proto"), content )    
            )
        |> Dict.fromList        