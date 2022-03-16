module Morphir.Elm.IncrementalFrontendTests exposing (..)

import Dict
import Expect
import Morphir.Elm.IncrementalFrontend as IncrementalFrontend
import Morphir.File.FileChanges exposing (Change(..), FileChanges)
import Test exposing (Test, describe, test)


parseElmModulesTest : Test
parseElmModulesTest =
    let
        source1 =
            String.join "\n"
                [ "module Morphir.Elm.ParsedModules exposing (..)"
                , ""
                , "type alias ParsedModules ="
                , "  String"
                ]

        source2 =
            String.join "\n"
                [ "module Morphir.Elm.Name exposing (..)"
                , ""
                , "type alias Name ="
                , " List String"
                , ""
                , "toTitleCase : Name -> String"
                , "toTitleCase name ="
                , " name"
                , "    |> toList"
                , "    |> List.map capitalize"
                , "    |> String.concat"
                ]

        source3 =
            String.join "\n"
                [ "module Morphir.Elm.FileChanges exposing (..)"
                , ""
                , "type Change"
                , "  = Insert String"
                , "  | Update String"
                , "  | Delete"
                , ""
                , "type alias FileChanges ="
                , "  Dict String Change"
                ]

        fileChangesWithoutDelete : FileChanges
        fileChangesWithoutDelete =
            Dict.fromList
                [ ( "/Morphir/Elm/ParsedModules", Insert source1 )
                , ( "/Morphir/Elm/Name", Insert source2 )
                , ( "/Morphir/Elm/FileChanges", Update source3 )
                ]

        fileChangesWithDelete : FileChanges
        fileChangesWithDelete =
            Dict.fromList
                [ ( "/Morphir/Elm/ParsedModules", Insert source1 )
                , ( "/Morphir/Elm/Name", Insert source2 )
                , ( "/Morphir/Elm/FileChanges", Delete )
                ]

        fileChangesWithOnlyDelete : FileChanges
        fileChangesWithOnlyDelete =
            Dict.fromList
                [ ( "/Morphir/Elm/ParsedModules", Delete )
                , ( "/Morphir/Elm/Name", Delete )
                , ( "/Morphir/Elm/FileChanges", Delete )
                ]
    in
    describe "Parse Elm Modules"
        [ test "2 Inserted, 1 Updated should result in 3 parsed modules" <|
            \_ ->
                fileChangesWithoutDelete
                    |> IncrementalFrontend.parseElmModules
                    |> Result.map List.length
                    |> Expect.equal (Ok 3)
        , test "2 Inserted, 1 Deleted should result in 2 parsed modules" <|
            \_ ->
                fileChangesWithDelete
                    |> IncrementalFrontend.parseElmModules
                    |> Result.map List.length
                    |> Expect.equal (Ok 2)
        , test "3 Deleted should result in 0 parsed modules" <|
            \_ ->
                fileChangesWithOnlyDelete
                    |> IncrementalFrontend.parseElmModules
                    |> Result.map List.length
                    |> Expect.equal (Ok 0)
        ]
