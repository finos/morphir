module Morphir.Type.SolveTests exposing (..)

import Dict
import Expect
import Morphir.IR.AccessControlled exposing (public)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.Package as Package
import Morphir.IR.SDK as SDK
import Morphir.IR.SDK.Basics exposing (boolType, intType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type as Type
import Morphir.Type.MetaType as MetaType exposing (MetaType(..), Variable, metaAlias, metaClosedRecord, metaFun, metaOpenRecord, variableByIndex)
import Morphir.Type.Solve as Solve exposing (SolutionMap, unifyMetaType)
import Test exposing (Test, describe, test)


substituteVariableTests : Test
substituteVariableTests =
    let
        assert : String -> SolutionMap -> ( Variable, MetaType ) -> SolutionMap -> Test
        assert msg original ( var, replacement ) expected =
            test msg
                (\_ ->
                    original
                        |> Solve.substituteVariable var replacement
                        |> Expect.equal expected
                )
    in
    describe "substituteVariable"
        [ assert "substitute variable"
            (Solve.fromList
                [ ( variableByIndex 0, MetaVar (variableByIndex 1) )
                ]
            )
            ( variableByIndex 1, MetaVar (variableByIndex 2) )
            (Solve.fromList
                [ ( variableByIndex 0, MetaVar (variableByIndex 2) )
                ]
            )
        , assert "substitute extensible record"
            (Solve.fromList
                [ ( variableByIndex 0, metaOpenRecord (variableByIndex 1) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ]) )
                ]
            )
            ( variableByIndex 1, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaClosedRecord (variableByIndex 4) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
            (Solve.fromList
                [ ( variableByIndex 0, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaClosedRecord (variableByIndex 4) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                ]
            )
        , assert "substitute wrapped extensible record"
            (Solve.fromList
                [ ( variableByIndex 0, metaFun (metaOpenRecord (variableByIndex 1) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) (MetaVar (variableByIndex 4)) )
                ]
            )
            ( variableByIndex 1, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaClosedRecord (variableByIndex 4) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
            (Solve.fromList
                [ ( variableByIndex 0, metaFun (metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaClosedRecord (variableByIndex 4) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ]))) (MetaVar (variableByIndex 4)) )
                ]
            )
        ]


addSolutionTests : Test
addSolutionTests =
    let
        assert : String -> SolutionMap -> ( Variable, MetaType ) -> SolutionMap -> Test
        assert msg original ( var, newSolution ) expected =
            test msg
                (\_ ->
                    original
                        |> Solve.addSolution (Library [ [ "empty" ] ] Dict.empty Package.emptyDefinition) var newSolution
                        |> Expect.equal (Ok expected)
                )
    in
    describe "addSolution"
        [ assert "substitute extensible record"
            (Solve.fromList
                [ ( variableByIndex 0, metaOpenRecord (variableByIndex 1) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ]) )
                ]
            )
            ( variableByIndex 1, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaClosedRecord (variableByIndex 4) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
            (Solve.fromList
                [ ( variableByIndex 0, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaClosedRecord (variableByIndex 4) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                , ( variableByIndex 1, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaClosedRecord (variableByIndex 4) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                ]
            )
        , assert "substitute extensible record reversed"
            (Solve.fromList
                [ ( variableByIndex 1, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaClosedRecord (variableByIndex 4) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                ]
            )
            ( variableByIndex 0, metaOpenRecord (variableByIndex 1) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ]) )
            (Solve.fromList
                [ ( variableByIndex 0, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaClosedRecord (variableByIndex 4) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                , ( variableByIndex 1, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaClosedRecord (variableByIndex 4) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                ]
            )
        , assert "substitute wrapped extensible record reversed"
            (Solve.fromList
                [ ( variableByIndex 1, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaClosedRecord (variableByIndex 4) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                ]
            )
            ( variableByIndex 0, metaFun (metaOpenRecord (variableByIndex 1) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) (MetaVar (variableByIndex 4)) )
            (Solve.fromList
                [ ( variableByIndex 0, metaFun (metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaClosedRecord (variableByIndex 4) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ]))) (MetaVar (variableByIndex 4)) )
                , ( variableByIndex 1, metaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) [] (metaClosedRecord (variableByIndex 4) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                ]
            )
        ]


unifyTests : Test
unifyTests =
    let
        assert : String -> MetaType -> MetaType -> SolutionMap -> Test
        assert testName metaType1 metaType2 expectedResult =
            test testName
                (\_ ->
                    unifyMetaType testIR [] metaType1 metaType2
                        |> Expect.equal (Ok expectedResult)
                )
    in
    describe "unifyMetaType"
        [ assert "alias 1"
            (metaOpenRecord (variableByIndex 0)
                (Dict.fromList
                    [ ( [ "foo" ], MetaType.stringType )
                    , ( [ "bar" ], MetaType.boolType )
                    , ( [ "baz" ], MetaType.intType )
                    ]
                )
            )
            (metaAlias (fqn "Test" "Test" "FooBarBazRecord")
                []
                (metaClosedRecord (variableByIndex 0)
                    (Dict.fromList
                        [ ( [ "foo" ], MetaType.stringType )
                        , ( [ "bar" ], MetaType.boolType )
                        , ( [ "baz" ], MetaType.intType )
                        ]
                    )
                )
            )
            (Solve.fromList
                [ ( variableByIndex 0
                  , metaAlias (fqn "Test" "Test" "FooBarBazRecord")
                        []
                        (metaClosedRecord (variableByIndex 0)
                            (Dict.fromList
                                [ ( [ "foo" ], MetaType.stringType )
                                , ( [ "bar" ], MetaType.boolType )
                                , ( [ "baz" ], MetaType.intType )
                                ]
                            )
                        )
                  )
                ]
            )
        , assert "alias 2"
            (metaAlias (fqn "Test" "Test" "FooBarBazRecord")
                []
                (metaClosedRecord (variableByIndex 0)
                    (Dict.fromList
                        [ ( [ "foo" ], MetaType.stringType )
                        , ( [ "bar" ], MetaType.boolType )
                        , ( [ "baz" ], MetaType.intType )
                        ]
                    )
                )
            )
            (metaOpenRecord (variableByIndex 0)
                (Dict.fromList
                    [ ( [ "foo" ], MetaType.stringType )
                    , ( [ "bar" ], MetaType.boolType )
                    , ( [ "baz" ], MetaType.intType )
                    ]
                )
            )
            (Solve.fromList
                [ ( variableByIndex 0
                  , metaAlias (fqn "Test" "Test" "FooBarBazRecord")
                        []
                        (metaClosedRecord (variableByIndex 0)
                            (Dict.fromList
                                [ ( [ "foo" ], MetaType.stringType )
                                , ( [ "bar" ], MetaType.boolType )
                                , ( [ "baz" ], MetaType.intType )
                                ]
                            )
                        )
                  )
                ]
            )
        ]


testIR : Distribution
testIR =
    Library [ [ "test" ] ]
        (Dict.fromList
            [ ( [ [ "morphir" ], [ "s", "d", "k" ] ]
              , SDK.packageSpec
              )
            ]
        )
        { modules =
            Dict.fromList
                [ ( [ [ "test" ] ]
                  , public <|
                        { types =
                            Dict.fromList
                                [ ( [ "custom" ]
                                  , public <|
                                        Documented ""
                                            (Type.CustomTypeDefinition []
                                                (public <|
                                                    Dict.fromList
                                                        [ ( [ "custom", "zero" ], [] )
                                                        ]
                                                )
                                            )
                                  )
                                , ( [ "foo", "bar", "baz", "record" ]
                                  , public <|
                                        Documented ""
                                            (Type.TypeAliasDefinition []
                                                (Type.Record ()
                                                    [ Type.Field [ "foo" ] (stringType ())
                                                    , Type.Field [ "bar" ] (boolType ())
                                                    , Type.Field [ "baz" ] (intType ())
                                                    ]
                                                )
                                            )
                                  )
                                ]
                        , values =
                            Dict.empty
                        , doc = Nothing
                        }
                  )
                ]
        }
