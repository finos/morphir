module Morphir.IR.Repo.RepoTest exposing (..)

import Dict
import Expect
import Morphir.Dependency.DAG as DAG
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled, public)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Repo as Repo exposing (Error(..), Errors, Repo)
import Morphir.IR.Type exposing (Definition(..), Type(..))
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
                                    Repo.insertModule modName modDef Public r
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
                            |> Repo.modules
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
            toModuleName "Morphir.IR.IncrementalFrontend"

        moduleName2 =
            toModuleName "Morphir.IR.DAG"

        repo : Repo
        repo =
            Repo.empty packageName
                |> Repo.insertModule moduleName Module.emptyDefinition Public
                |> Result.withDefault (Repo.empty packageName)

        typeList : List ( Name, Definition () )
        typeList =
            [ ( [ "my", "pi" ], TypeAliasDefinition [ [ "my", "pi" ] ] (Variable () [ "3.142" ]) )
            , ( [ "my", "errors" ], TypeAliasDefinition [ [ "my", "errors" ] ] (Variable () [ "TypeCycleDetected", "ValueCycleDetected" ]) )
            ]

        cyclicTypeList : List ( Name, Definition () )
        cyclicTypeList =
            [ ( [ "my", "pi" ], TypeAliasDefinition [] (Reference () ( packageName, moduleName, [ "my", "error" ] ) []) )
            , ( [ "my", "error" ], TypeAliasDefinition [] (Reference () ( packageName, moduleName, [ "my", "pi" ] ) []) )
            ]

        cyclicModuleTypeList : List ( Name, Definition (), ModuleName )
        cyclicModuleTypeList =
            [ ( [ "my", "pi" ], TypeAliasDefinition [] (Reference () ( packageName, moduleName2, [ "a", "variable" ] ) []), moduleName )
            , ( [ "my", "error" ], TypeAliasDefinition [] (Reference () ( packageName, moduleName, [ "another", "variable" ] ) []), moduleName2 )
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
                            |> Result.andThen (Repo.insertType moduleName typeName typeDef Public "")
                    )
                    (Ok repo)

        runSuccessfulInsertTest : List ( Name, Definition () ) -> Int
        runSuccessfulInsertTest parsedTypeList =
            parsedTypeList
                |> repoInsertTypeMethod
                |> Result.withDefault repo
                |> Repo.modules
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

                    Err _ ->
                        Expect.pass
            )
        , test "Checking For Valid Type Dependency DAG"
            (\_ ->
                typeList
                    |> repoInsertTypeMethod
                    |> (\validRepo ->
                            case validRepo of
                                Ok r ->
                                    Repo.typeDependencies r
                                        |> Expect.notEqual DAG.empty

                                Err _ ->
                                    Expect.fail "Type Dependency DAG Empty"
                       )
            )
        , test "Should fail to insert Cyclic Type"
            (\_ ->
                cyclicTypeList
                    |> repoInsertTypeMethod
                    |> (\invalidRepo ->
                            case invalidRepo of
                                Ok _ ->
                                    Expect.fail "should fail with a CycleDetected Error"

                                Err _ ->
                                    Expect.pass
                       )
            )
        , test "should fail to insert type if type causes Cyclic module dependency"
            (\_ ->
                let
                    updatedRepo =
                        Repo.insertModule (toModuleName "Morphir.IR.DAG") Module.emptyDefinition Public repo

                    insertTypes =
                        cyclicModuleTypeList
                            |> List.foldl
                                (\( name, def, modname ) repoSoFar ->
                                    repoSoFar
                                        |> Result.andThen (Repo.insertType modname name def Public "")
                                )
                                updatedRepo
                in
                case insertTypes of
                    Ok _ ->
                        Expect.fail "should fail with Cyclic Module Dependency"

                    Err _ ->
                        Expect.pass
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
                |> Repo.insertModule moduleName Module.emptyDefinition Public
                |> Result.withDefault (Repo.empty packageName)

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

        valueListWithCyclicModuleDeps : List ( Name, Value.Definition () (Type ()), ModuleName )
        valueListWithCyclicModuleDeps =
            [ ( [ "foo" ]
              , { inputTypes = []
                , outputType = Unit ()
                , body = Value.Reference (Unit ()) ( packageName, toModuleName "Morphir.IR.DAG", [ "bar" ] )
                }
              , moduleName
              )
            , ( [ "bar" ]
              , { inputTypes = []
                , outputType = Unit ()
                , body = Value.Reference (Unit ()) ( packageName, moduleName, [ "foo" ] )
                }
              , toModuleName "Morphir.IR.DAG"
              )
            ]

        cyclicValueList =
            [ ( [ "foo" ]
              , { inputTypes = []
                , outputType = Unit ()
                , body = Value.Reference (Unit ()) ( packageName, moduleName, [ "bar" ] )
                }
              )
            , ( [ "bar" ]
              , { inputTypes = []
                , outputType = Unit ()
                , body = Value.Reference (Unit ()) ( packageName, moduleName, [ "foo" ] )
                }
              )
            ]

        repoInsertValueMethod : List ( Name, Value.Definition () (Type ()) ) -> Repo -> Result Errors Repo
        repoInsertValueMethod valueList currentRepo =
            valueList
                |> List.foldl
                    (\( valueName, valueDef ) repoResultSoFar ->
                        repoResultSoFar
                            |> Result.andThen (Repo.insertTypedValue moduleName valueName valueDef Public "")
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
                                    Repo.modules currentRepo
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
                                    Repo.valueDependencies r
                                        |> DAG.toList
                                        |> Expect.notEqual []

                                Err _ ->
                                    Expect.fail "Type Dependency DAG Empty"
                       )
            )
        , test "Should fail to insert Cyclic Value Reference"
            (\_ ->
                repo
                    |> repoInsertValueMethod cyclicValueList
                    |> (\invalidRepo ->
                            case invalidRepo of
                                Ok _ ->
                                    Expect.fail "should fail with a CycleDetected Error"

                                Err _ ->
                                    Expect.pass
                       )
            )
        , test "should fail to insert type if type causes Cyclic module dependency"
            (\_ ->
                let
                    updatedRepo =
                        Repo.insertModule (toModuleName "Morphir.IR.DAG") Module.emptyDefinition Public repo

                    insertValues =
                        valueListWithCyclicModuleDeps
                            |> List.foldl
                                (\( name, def, modname ) repoSoFar ->
                                    repoSoFar
                                        |> Result.andThen (Repo.insertTypedValue modname name def Public "")
                                )
                                updatedRepo
                in
                case insertValues of
                    Ok _ ->
                        Expect.fail "should fail with Cyclic Module Dependency"

                    Err _ ->
                        Expect.pass
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
        |> Repo.insertModule moduleName Module.emptyDefinition Public
        |> Result.andThen
            (Repo.insertType moduleName typeName typeDef Public "")
        |> Result.andThen
            (Repo.insertTypedValue moduleName valueName valueDef Public "")
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
