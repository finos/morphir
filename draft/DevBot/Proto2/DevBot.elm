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