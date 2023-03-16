module Morphir.Elm.IncrementalFrontendTests exposing (..)

import Dict exposing (Dict)
import Elm.Parser
import Expect
import Morphir.Elm.IncrementalFrontend as IncrementalFrontend
import Morphir.Elm.ParsedModule exposing (parsedModule)
import Morphir.File.FileChanges exposing (Change(..), FileChanges)
import Morphir.IR.AccessControlled exposing (Access(..), private, public)
import Morphir.IR.FQName as FQName exposing (fqn)
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value
import Parser exposing (DeadEnd)
import Set exposing (Set)
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
                                        listOfNameAndDefs
                                            |> List.map (\( name, _, def ) -> ( name, def ))
                                            |> cb

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


implicitExposedModulesTest : Test
implicitExposedModulesTest =
    let
        morphirPackage =
            Path.fromString "Morphir.SDK"

        listRef a =
            Type.Reference () ( morphirPackage, Path.fromString "List", Name.fromString "List" ) [ a ]

        stringRef =
            Type.Reference () ( morphirPackage, Path.fromString "String", Name.fromString "String" ) []

        intRef =
            Type.Reference () ( morphirPackage, Path.fromString "Basics", Name.fromString "Int" ) []

        packageName =
            Path.fromString "Mods"

        tableModule =
            Path.fromString "Table"

        rowModule =
            Path.fromString "Row"

        unitModule =
            Path.fromString "Unit"

        publicModule =
            Path.fromString "PublicModule"

        publicModule2 =
            Path.fromString "PublicModule2"

        functionInputTypesModule =
            Path.fromString "FunctionInput"

        functionOutputTypesModule =
            Path.fromString "FunctionOutput"

        publicFunctionsModule =
            Path.fromString "PublicFunction"

        exposedModules : Set Path
        exposedModules =
            Set.fromList
                [ publicModule
                , publicModule2
                , publicFunctionsModule
                ]

        modules : Dict Path (Module.Definition () ())
        modules =
            let
                emptyDef : Module.Definition () ()
                emptyDef =
                    Module.emptyDefinition
            in
            Dict.fromList
                [ ( publicModule
                  , { emptyDef
                        | types =
                            Dict.fromList
                                [ ( Name.fromString "Name"
                                  , public
                                        { doc = ""
                                        , value =
                                            Type.CustomTypeDefinition []
                                                (private
                                                    (Dict.fromList
                                                        [ ( Name.fromString "Name"
                                                          , [ ( Name.fromString "arg1"
                                                              , Type.Reference ()
                                                                    (fqn "Morphir.SDK" "String" "String")
                                                                    []
                                                              )
                                                            ]
                                                          )
                                                        ]
                                                    )
                                                )
                                        }
                                  )
                                , ( Name.fromString "UserTable"
                                  , public
                                        { doc = ""
                                        , value =
                                            Type.TypeAliasDefinition []
                                                (Type.Reference ()
                                                    ( packageName, tableModule, Name.fromString "Table" )
                                                    []
                                                )
                                        }
                                  )
                                ]
                    }
                  )
                , ( tableModule
                  , { emptyDef
                        | types =
                            Dict.fromList
                                [ ( Name.fromString "Table"
                                  , public
                                        { doc = ""
                                        , value =
                                            Type.TypeAliasDefinition []
                                                (listRef
                                                    (Type.Reference ()
                                                        ( packageName, rowModule, Name.fromString "Row" )
                                                        []
                                                    )
                                                )
                                        }
                                  )
                                , ( Name.fromString "TablePadding"
                                  , public
                                        { doc = ""
                                        , value =
                                            Type.TypeAliasDefinition []
                                                (Type.Record ()
                                                    [ Type.Field (Name.fromString "size")
                                                        (Type.Reference ()
                                                            ( packageName, publicModule2, Name.fromString "Size" )
                                                            []
                                                        )
                                                    , Type.Field (Name.fromString "unit")
                                                        (Type.Reference ()
                                                            ( packageName, unitModule, Name.fromString "Unit" )
                                                            []
                                                        )
                                                    ]
                                                )
                                        }
                                  )
                                ]
                    }
                  )
                , ( rowModule
                  , { emptyDef
                        | types =
                            Dict.fromList
                                [ ( Name.fromString "Row"
                                  , public
                                        { doc = ""
                                        , value =
                                            Type.TypeAliasDefinition []
                                                (Type.Record ()
                                                    [ Type.Field (Name.fromString "col1") stringRef
                                                    , Type.Field (Name.fromString "col2") stringRef
                                                    ]
                                                )
                                        }
                                  )
                                ]
                    }
                  )
                , ( unitModule
                  , { emptyDef
                        | types =
                            Dict.fromList
                                [ ( Name.fromString "Unit"
                                  , public
                                        { doc = ""
                                        , value =
                                            Type.CustomTypeDefinition []
                                                (public
                                                    (Dict.fromList
                                                        [ ( Name.fromString "PX", [] )
                                                        , ( Name.fromString "REM", [] )
                                                        , ( Name.fromString "INCH", [] )
                                                        , ( Name.fromString "FT", [] )
                                                        ]
                                                    )
                                                )
                                        }
                                  )
                                ]
                    }
                  )
                , ( publicModule2
                  , { emptyDef
                        | types =
                            Dict.fromList
                                [ ( Name.fromString "Size"
                                  , public
                                        { doc = ""
                                        , value =
                                            Type.TypeAliasDefinition []
                                                intRef
                                        }
                                  )
                                ]
                    }
                  )
                , ( functionInputTypesModule
                  , { emptyDef
                        | types =
                            Dict.fromList
                                [ ( Name.fromString "InputType"
                                  , public
                                        { doc = ""
                                        , value =
                                            Type.TypeAliasDefinition []
                                                intRef
                                        }
                                  )
                                ]
                    }
                  )
                , ( functionOutputTypesModule
                  , { emptyDef
                        | types =
                            Dict.fromList
                                [ ( Name.fromString "OutputType"
                                  , public
                                        { doc = ""
                                        , value =
                                            Type.TypeAliasDefinition []
                                                intRef
                                        }
                                  )
                                ]
                    }
                  )
                , ( publicFunctionsModule
                  , { emptyDef
                        | values =
                            Dict.fromList
                                [ ( Name.fromString "InputType"
                                  , public
                                        { doc = ""
                                        , value =
                                            { inputTypes = [ ( Name.fromString "a", (), Type.Reference () ( packageName, functionInputTypesModule, Name.fromString "InputType" ) [] ) ]
                                            , outputType = Type.Reference () ( packageName, functionOutputTypesModule, Name.fromString "OutputType" ) []
                                            , body =
                                                Value.Variable ()
                                                    (Name.fromString "a")
                                            }
                                        }
                                  )
                                ]
                    }
                  )
                ]

        expectIsImplicitlyExposed : String -> Path -> Test
        expectIsImplicitlyExposed testName modName =
            test testName <|
                \_ ->
                    Expect.equal True
                        (Set.member modName <|
                            IncrementalFrontend.collectImplicitlyExposedModules packageName
                                modules
                                exposedModules
                        )

        expectIsNotImplicitlyExposed : String -> Path -> Test
        expectIsNotImplicitlyExposed testName modName =
            test testName <|
                \_ ->
                    Expect.equal False
                        (Set.member modName <|
                            IncrementalFrontend.collectImplicitlyExposedModules packageName
                                modules
                                exposedModules
                        )
    in
    describe "Implicitly exposed modules"
        [ expectIsNotImplicitlyExposed (Path.toString Name.toTitleCase "." publicModule ++ " is not implicitly exposed because It's explicitly exposed")
            publicModule
        , expectIsNotImplicitlyExposed (Path.toString Name.toTitleCase "." publicModule2 ++ " is not implicitly exposed because It's explicitly exposed")
            publicModule2
        , expectIsImplicitlyExposed (Path.toString Name.toTitleCase "." tableModule ++ " is implicitly exposed by PublicModule")
            tableModule
        , expectIsImplicitlyExposed (Path.toString Name.toTitleCase "." rowModule ++ " is implicitly exposed by PublicModule")
            rowModule
        , expectIsNotImplicitlyExposed (Path.toString Name.toTitleCase "." unitModule ++ " is not implicitly or explicitly exposed")
            unitModule
        , expectIsNotImplicitlyExposed (Path.toString Name.toTitleCase "." publicFunctionsModule ++ " is not implicitly exposed because It's explicitly exposed")
            publicFunctionsModule
        , expectIsImplicitlyExposed (Path.toString Name.toTitleCase "." functionInputTypesModule ++ " is implicitly exposed by PublicFunction")
            functionInputTypesModule
        , expectIsImplicitlyExposed (Path.toString Name.toTitleCase "." functionOutputTypesModule ++ " is implicitly exposed by PublicFunction")
            functionOutputTypesModule
        ]
