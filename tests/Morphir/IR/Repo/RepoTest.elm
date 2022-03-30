module Morphir.IR.Repo.RepoTest exposing (..)

import Dict
import Expect
import Morphir.Dependency.DAG as DAG
import Morphir.IR.AccessControlled exposing (AccessControlled, public)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Repo as Repo exposing (Error(..), Errors, Repo)
import Morphir.IR.Type as Type exposing (Definition(..), Type(..))
import Morphir.IR.Value as Value
import Test exposing (Test, describe, test)


toModuleName : String -> ModuleName
toModuleName string =
    [ Name.fromString string ]


packageName =
    [ Name.fromString "Morphir.IR" ]


insertModuleTest : Test
insertModuleTest =
    let
        repo =
            Repo.empty packageName

        modules =
            [ ( toModuleName "Morphir.IR.Repo", Module.emptyDefinition )
            , ( toModuleName "Morphir.IR.Elm", Module.emptyDefinition )
            ]

        duplicateModules =
            [ ( toModuleName "Morphir.IR.Distribution", Module.emptyDefinition )
            , ( toModuleName "Morphir.IR.Distribution", Module.emptyDefinition )
            ]

        insertModuleIntoRepo : List ( ModuleName, Module.Definition () (Type ()) ) -> Repo -> Result Errors Repo
        insertModuleIntoRepo moduleList localRepo =
            moduleList
                |> List.foldl
                    (\( modName, modDef ) repoResultSoFar ->
                        repoResultSoFar
                            |> Result.andThen
                                (\r ->
                                    Repo.insertModule modName modDef r
                                )
                    )
                    (Ok localRepo)
    in
    describe "Test Module insertion into Repo"
        [ test "Inserting Unique Modules into repo"
            (\_ ->
                case repo |> insertModuleIntoRepo modules of
                    Ok validRepo ->
                        validRepo
                            |> .modules
                            >> Dict.size
                            |> Expect.equal 2

                    Err _ ->
                        Expect.fail "Should Have Inserted Successfully"
            )
        , test "Inserting Duplicate Modules into repo"
            (\_ ->
                case repo |> insertModuleIntoRepo duplicateModules of
                    Ok _ ->
                        Expect.fail "Insertion Into Repo Should Have Failed"

                    Err _ ->
                        Expect.pass
            )
        ]


insertTypeTest : Test
insertTypeTest =
    let
        moduleName =
            toModuleName "Morphir.IR.Distribution"

        repo : Repo
        repo =
            Repo.empty packageName
                |> (\r ->
                        { r
                            | modules =
                                Dict.fromList
                                    [ ( moduleName, public Module.emptyDefinition )
                                    ]
                        }
                   )

        typeList : List ( Name, Definition () )
        typeList =
            [ ( [ "my", "pi" ], TypeAliasDefinition [ [ "my", "pi" ] ] (Variable () [ "3.142" ]) )
            , ( [ "my", "errors" ], TypeAliasDefinition [ [ "my", "errors" ] ] (Variable () [ "TypeCycleDetected", "ValueCycleDetected" ]) )
            ]

        duplicateTypeList : List ( Name, Definition () )
        duplicateTypeList =
            [ ( [ "my", "pi" ], TypeAliasDefinition [ [ "my", "pi" ] ] (Variable () [ "3.142" ]) )
            , ( [ "my", "pi" ], TypeAliasDefinition [ [ "my", "pi" ] ] (Variable () [ "3.142" ]) )
            ]

        repoInsertTypeMethod : List ( Name, Definition () ) -> Result Errors Repo
        repoInsertTypeMethod internalTypeList =
            internalTypeList
                |> List.foldl
                    (\( typeName, typeDef ) repoResultSoFar ->
                        repoResultSoFar
                            |> Result.andThen (Repo.insertType moduleName typeName typeDef)
                    )
                    (Ok repo)

        runSuccessfulInsertTest : List ( Name, Definition () ) -> Int
        runSuccessfulInsertTest parsedTypeList =
            parsedTypeList
                |> repoInsertTypeMethod
                |> Result.withDefault repo
                |> .modules
                |> Dict.get moduleName
                |> Maybe.withDefault (public Module.emptyDefinition)
                |> .value
                |> .types
                |> Dict.size
    in
    describe "Testing Insert Type into Repo Module"
        [ test "Successful Type Insert into Module"
            (\_ ->
                typeList
                    |> runSuccessfulInsertTest
                    |> Expect.equal 2
            )
        , test "Insertion of Types Fails Test"
            (\_ ->
                case repoInsertTypeMethod duplicateTypeList of
                    Ok _ ->
                        Expect.fail "Duplicate Type Should Have Failed"

                    Err err ->
                        Expect.pass
            )
        , test "Checking For Valid Type Dependency DAG"
            (\_ ->
                typeList
                    |> repoInsertTypeMethod
                    |> (\validRepo ->
                            case validRepo of
                                Ok r ->
                                    r.typeDependencies
                                        |> Expect.notEqual DAG.empty

                                Err _ ->
                                    Expect.fail "Type Dependency DAG Empty"
                       )
            )
        ]


insertValueTest : Test
insertValueTest =
    let
        moduleName =
            toModuleName "Morphir.IR.Distribution"

        repo : Repo
        repo =
            Repo.empty packageName
                |> (\r ->
                        { r
                            | modules =
                                Dict.fromList
                                    [ ( moduleName, public Module.emptyDefinition )
                                    ]
                        }
                   )

        uniqueValueList : List ( Name, Value.Definition () (Type ()) )
        uniqueValueList =
            [ ( [ "empty", "function" ]
              , { inputTypes = []
                , outputType = Unit ()
                , body = Value.Literal (Unit ()) (WholeNumberLiteral 0)
                }
              )
            , ( [ "param", "function" ]
              , { inputTypes = []
                , outputType = Unit ()
                , body = Value.Literal (Unit ()) (WholeNumberLiteral 44)
                }
              )
            ]

        duplicateValueList : List ( Name, Value.Definition () (Type ()) )
        duplicateValueList =
            [ ( [ "empty", "Function" ]
              , { inputTypes = []
                , outputType = Unit ()
                , body = Value.Literal (Unit ()) (WholeNumberLiteral 25)
                }
              )
            , ( [ "empty", "Function" ]
              , { inputTypes = []
                , outputType = Unit ()
                , body = Value.Literal (Unit ()) (WholeNumberLiteral 25)
                }
              )
            ]

        repoInsertValueMethod : List ( Name, Value.Definition () (Type ()) ) -> Repo -> Result Errors Repo
        repoInsertValueMethod valueList currentRepo =
            valueList
                |> List.foldl
                    (\( valueName, valueDef ) repoResultSoFar ->
                        repoResultSoFar
                            |> Result.andThen (Repo.insertValue moduleName valueName valueDef)
                    )
                    (Ok currentRepo)
    in
    describe "Testing Value Insertion into Repo Module"
        [ test "Successful Unique Values Insertion into repo module"
            (\_ ->
                repo
                    |> repoInsertValueMethod uniqueValueList
                    |> (\insertResult ->
                            case insertResult of
                                Ok currentRepo ->
                                    currentRepo.modules
                                        |> Dict.get moduleName
                                        |> Maybe.withDefault (public Module.emptyDefinition)
                                        |> .value
                                        |> .values
                                        |> Dict.size
                                        |> Expect.equal 2

                                Err _ ->
                                    Expect.fail "Unique Values Insertion Failed"
                       )
            )
        , test "Insertion of Duplicate Values Fails Test"
            (\_ ->
                case repo |> repoInsertValueMethod duplicateValueList of
                    Ok _ ->
                        Expect.fail "Duplicate Values Should Have Failed"

                    Err _ ->
                        Expect.pass
            )
        , test "Checking For Valid Values Dependency DAG"
            (\_ ->
                repo
                    |> repoInsertValueMethod uniqueValueList
                    |> (\validRepo ->
                            case validRepo of
                                Ok r ->
                                    r.valueDependencies
                                        |> Expect.notEqual DAG.empty

                                Err _ ->
                                    Expect.fail "Type Dependency DAG Empty"
                       )
            )
        ]


toDistributionTest : Test
toDistributionTest =
    let
        moduleName =
            toModuleName "Morphir.IR.Distribution"

        typeName =
            [ "my", "pi" ]

        typeDef =
            TypeAliasDefinition [ [ "my", "pi" ] ] (Variable () [ "3.142" ])

        valueName =
            [ "empty", "function" ]

        valueDef =
            { inputTypes = []
            , outputType = Unit ()
            , body = Value.Literal (Unit ()) (WholeNumberLiteral 0)
            }
    in
    packageName
        |> Repo.empty
        |> Repo.insertModule moduleName Module.emptyDefinition
        |> Result.andThen
            (Repo.insertType moduleName typeName typeDef)
        |> Result.andThen
            (Repo.insertValue moduleName valueName valueDef)
        |> (\validRepo ->
                case validRepo of
                    Ok r ->
                        case r |> Repo.toDistribution of
                            Library _ _ _ ->
                                test "repo converted to distribution successfully"
                                    (\_ ->
                                        Expect.pass
                                    )

                    Err _ ->
                        test "repo to distribution failed"
                            (\_ ->
                                Expect.fail "repo to distribution failed"
                            )
           )
