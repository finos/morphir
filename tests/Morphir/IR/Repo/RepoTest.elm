module Morphir.IR.Repo.RepoTest exposing (..)

import Dict
import Expect
import Morphir.IR.AccessControlled exposing (public)
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Repo as Repo exposing (Repo)
import Morphir.IR.Type as Type exposing (Definition(..), Type(..))
import Test exposing (Test, describe, test)


insertModuleTest : Test
insertModuleTest =
    let
        toModuleName : String -> ModuleName
        toModuleName string =
            [ Name.fromString string ]

        packageName =
            [ Name.fromString "Morphir.IR" ]

        repo =
            Repo.empty packageName

        modules =
            [ ( toModuleName "Morphir.IR.Repo", Module.emptyDefinition )
            , ( toModuleName "Morphir.IR.Elm", Module.emptyDefinition )
            , ( toModuleName "Morphir.IR.Distribution", Module.emptyDefinition )
            , ( toModuleName "Morphir.IR.Dependency", Module.emptyDefinition )
            ]

        runTestWithInsertModule : String -> List ( ModuleName, Module.Definition () (Type ()) ) -> Int -> Test
        runTestWithInsertModule name moduleList expectedSize =
            test name
                (\_ ->
                    moduleList
                        |> List.foldl
                            (\( modName, modDef ) repoResultSoFar ->
                                repoResultSoFar
                                    |> Result.andThen
                                        (\r ->
                                            Repo.insertModule modName modDef r
                                        )
                            )
                            (Ok repo)
                        |> Result.withDefault repo
                        |> .modules
                        >> Dict.size
                        |> Expect.equal expectedSize
                )
    in
    describe "Test Module insertion into Repo Api"
        [ runTestWithInsertModule "Inserting Modules into repo" modules 4
        ]


insertTypeTest : Test
insertTypeTest =
    let
        packageName =
            [ Name.fromString "Morphir.IR" ]

        moduleName =
            [ Name.fromString "Morphir.IR.Distribution" ]

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

        runTest : String -> List ( Name, Definition () ) -> Int -> Test
        runTest description types expectedValue =
            test description
                (\_ ->
                    types
                        |> List.foldl
                            (\( typeName, typeDef ) repoResultSoFar ->
                                repoResultSoFar
                                    |> Result.andThen (Repo.insertType moduleName typeName typeDef)
                            )
                            (Ok repo)
                        |> Result.withDefault repo
                        |> .modules
                        |> Dict.get moduleName
                        |> Maybe.withDefault (public Module.emptyDefinition)
                        |> .value
                        |> .types
                        |> Dict.size
                        |> Expect.equal expectedValue
                )
    in
    describe "Testing Insert Type into Repo Module Def"
        [ runTest "insert type into module def of repo api" typeList 2
        , runTest "insert type into module def of repo api" typeList 2
        ]


insertValuesTest : Test
insertValuesTest =
    Debug.todo "to be implemented"
