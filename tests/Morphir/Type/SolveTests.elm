module Morphir.Type.SolveTests exposing (..)

import Dict
import Expect
import Morphir.IR as IR
import Morphir.Type.MetaType as MetaType exposing (MetaType(..), Variable, variableByIndex)
import Morphir.Type.Solve as Solve exposing (SolutionMap)
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
                [ ( variableByIndex 0, MetaRecord (Just (variableByIndex 1)) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ]) )
                ]
            )
            ( variableByIndex 1, MetaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) (MetaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
            (Solve.fromList
                [ ( variableByIndex 0, MetaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) (MetaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                ]
            )
        , assert "substitute wrapped extensible record"
            (Solve.fromList
                [ ( variableByIndex 0, MetaFun (MetaRecord (Just (variableByIndex 1)) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) (MetaVar (variableByIndex 4)) )
                ]
            )
            ( variableByIndex 1, MetaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) (MetaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
            (Solve.fromList
                [ ( variableByIndex 0, MetaFun (MetaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) (MetaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ]))) (MetaVar (variableByIndex 4)) )
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
                        |> Solve.addSolution IR.empty var newSolution
                        |> Expect.equal (Ok expected)
                )
    in
    describe "addSolution"
        [ assert "substitute extensible record"
            (Solve.fromList
                [ ( variableByIndex 0, MetaRecord (Just (variableByIndex 1)) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ]) )
                ]
            )
            ( variableByIndex 1, MetaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) (MetaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
            (Solve.fromList
                [ ( variableByIndex 0, MetaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) (MetaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                , ( variableByIndex 1, MetaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) (MetaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                ]
            )
        , assert "substitute extensible record reversed"
            (Solve.fromList
                [ ( variableByIndex 1, MetaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) (MetaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                ]
            )
            ( variableByIndex 0, MetaRecord (Just (variableByIndex 1)) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ]) )
            (Solve.fromList
                [ ( variableByIndex 0, MetaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) (MetaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                , ( variableByIndex 1, MetaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) (MetaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                ]
            )
        , assert "substitute wrapped extensible record reversed"
            (Solve.fromList
                [ ( variableByIndex 1, MetaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) (MetaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                ]
            )
            ( variableByIndex 0, MetaFun (MetaRecord (Just (variableByIndex 1)) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) (MetaVar (variableByIndex 4)) )
            (Solve.fromList
                [ ( variableByIndex 0, MetaFun (MetaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) (MetaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ]))) (MetaVar (variableByIndex 4)) )
                , ( variableByIndex 1, MetaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) (MetaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                ]
            )
        ]
