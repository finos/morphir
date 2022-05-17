module Morphir.Elm.IncrementalFrontendTests exposing (..)

import Dict
import Elm.Parser
import Expect
import Morphir.Elm.IncrementalFrontend as IncrementalFrontend
import Morphir.Elm.ParsedModule exposing (parsedModule)
import Morphir.File.FileChanges exposing (Change(..), FileChanges)
import Morphir.IR.AccessControlled exposing (Access(..))
import Morphir.IR.FQName as FQName
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Type as Type
import Parser exposing (DeadEnd)
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


extractTypesTest : Test
extractTypesTest =
    let
        nameResolver _ localName _ =
            Ok (FQName.fqn "Morphir.Elm" "Morphir.Elm.Examlple" localName)

        accessOf _ _ =
            Public

        exampleModuleResult : Result (List DeadEnd) Morphir.Elm.ParsedModule.ParsedModule
        exampleModuleResult =
            String.join "\n"
                [ "module Morphir.Elm.Example exposing (..)"
                , ""
                , "type KindOfName = Type | Constructor | Value"
                , ""
                , "type alias Name = List String"
                , ""
                , "type alias Path = List Name"
                ]
                |> Elm.Parser.parse
                |> Result.map parsedModule

        runTestWithExtractTypes : String -> (List ( Name, Type.Definition () ) -> Expect.Expectation) -> Test
        runTestWithExtractTypes title cb =
            test title
                (\_ ->
                    exampleModuleResult
                        |> Result.mapError (IncrementalFrontend.ParseError "" >> List.singleton)
                        |> Result.andThen
                            (\parsedModule ->
                                IncrementalFrontend.extractTypes nameResolver accessOf parsedModule
                            )
                        |> (\extractedTypesResult ->
                                case extractedTypesResult of
                                    Ok listOfNameAndDefs ->
                                        cb listOfNameAndDefs

                                    Err _ ->
                                        Expect.fail "Failed to parse module"
                           )
                )
    in
    describe "extract types"
        [ runTestWithExtractTypes "should return 3 types"
            (List.length >> Expect.equal 3)
        , runTestWithExtractTypes "should contain KindOfName, Name, Path as a names in list"
            (List.filterMap (Tuple.first >> Name.toTitleCase >> Just)
                >> Expect.equal [ "KindOfName", "Name", "Path" ]
            )
        ]
