module Morphir.Correctness.BranchCoverageTests exposing (..)

import Expect
import Morphir.Correctness.BranchCoverage as BranchCoverage exposing (Branch, Condition(..))
import Morphir.Correctness.Test exposing (TestCase)
import Morphir.IR as IR
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.SDK.Basics exposing (intType)
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value
import Morphir.IR.Values exposing (apply, apply2, basics, litInt, unit, var)
import Test exposing (Test, describe, test)


valueBranchesTests : Test
valueBranchesTests =
    let
        assertExpand : String -> Value.Value ta va -> List (BranchCoverage.Branch ta va) -> Test
        assertExpand msg input expectedOutput =
            test msg
                (\_ ->
                    BranchCoverage.valueBranches True input
                        |> Expect.equal expectedOutput
                )

        assertNoExpand : String -> Value.Value ta va -> List (BranchCoverage.Branch ta va) -> Test
        assertNoExpand msg input expectedOutput =
            test (msg ++ " - no expand")
                (\_ ->
                    BranchCoverage.valueBranches False input
                        |> Expect.equal expectedOutput
                )
    in
    describe "valueBranches"
        [ assertExpand "single if/else"
            (Value.IfThenElse ()
                (eq "a" 1)
                unit
                unit
            )
            [ [ BoolCondition { criterion = eq "a" 1, expectedValue = True } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = False } ]
            ]
        , assertExpand "nested if/else - one branch"
            (Value.IfThenElse ()
                (eq "a" 1)
                (Value.IfThenElse ()
                    (eq "b" 2)
                    unit
                    unit
                )
                unit
            )
            [ [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = True } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = False } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = False } ]
            ]
        , assertExpand "nested if/else - both branches"
            (Value.IfThenElse ()
                (eq "a" 1)
                (Value.IfThenElse ()
                    (eq "b" 2)
                    unit
                    unit
                )
                (Value.IfThenElse ()
                    (eq "c" 3)
                    unit
                    unit
                )
            )
            [ [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = True } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = False } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = False }, BoolCondition { criterion = eq "c" 3, expectedValue = True } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = False }, BoolCondition { criterion = eq "c" 3, expectedValue = False } ]
            ]
        , assertExpand "single if/else - not"
            (Value.IfThenElse ()
                (not (eq "a" 1))
                unit
                unit
            )
            [ [ BoolCondition { criterion = eq "a" 1, expectedValue = False } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = True } ]
            ]
        , assertNoExpand "single if/else - not"
            (Value.IfThenElse ()
                (not (eq "a" 1))
                unit
                unit
            )
            [ [ BoolCondition { criterion = not (eq "a" 1), expectedValue = True } ]
            , [ BoolCondition { criterion = not (eq "a" 1), expectedValue = False } ]
            ]
        , assertExpand "single if/else - two criteria - and"
            (Value.IfThenElse ()
                (and
                    (eq "a" 1)
                    (eq "b" 2)
                )
                unit
                unit
            )
            [ [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = True } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = False } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = False }, BoolCondition { criterion = eq "b" 2, expectedValue = True } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = False }, BoolCondition { criterion = eq "b" 2, expectedValue = False } ]
            ]
        , assertNoExpand "single if/else - two criteria - and"
            (Value.IfThenElse ()
                (and (eq "a" 1) (eq "b" 2))
                unit
                unit
            )
            [ [ BoolCondition { criterion = and (eq "a" 1) (eq "b" 2), expectedValue = True } ]
            , [ BoolCondition { criterion = and (eq "a" 1) (eq "b" 2), expectedValue = False } ]
            ]
        , assertExpand "single if/else - two criteria - or"
            (Value.IfThenElse ()
                (or
                    (eq "a" 1)
                    (eq "b" 2)
                )
                unit
                unit
            )
            [ [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = False } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = False }, BoolCondition { criterion = eq "b" 2, expectedValue = True } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = True } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = False }, BoolCondition { criterion = eq "b" 2, expectedValue = False } ]
            ]
        , assertExpand "nested if/else - two criteria - and"
            (Value.IfThenElse ()
                (and
                    (eq "a" 1)
                    (eq "b" 2)
                )
                (Value.IfThenElse ()
                    (eq "c" 3)
                    unit
                    unit
                )
                (Value.IfThenElse ()
                    (eq "d" 4)
                    unit
                    unit
                )
            )
            [ [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = True }, BoolCondition { criterion = eq "c" 3, expectedValue = True } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = True }, BoolCondition { criterion = eq "c" 3, expectedValue = False } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = False }, BoolCondition { criterion = eq "d" 4, expectedValue = True } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = False }, BoolCondition { criterion = eq "d" 4, expectedValue = False } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = False }, BoolCondition { criterion = eq "b" 2, expectedValue = True }, BoolCondition { criterion = eq "d" 4, expectedValue = True } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = False }, BoolCondition { criterion = eq "b" 2, expectedValue = True }, BoolCondition { criterion = eq "d" 4, expectedValue = False } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = False }, BoolCondition { criterion = eq "b" 2, expectedValue = False }, BoolCondition { criterion = eq "d" 4, expectedValue = True } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = False }, BoolCondition { criterion = eq "b" 2, expectedValue = False }, BoolCondition { criterion = eq "d" 4, expectedValue = False } ]
            ]
        , assertExpand "nested if/else - two criteria - or"
            (Value.IfThenElse ()
                (or
                    (eq "a" 1)
                    (eq "b" 2)
                )
                (Value.IfThenElse ()
                    (eq "c" 3)
                    unit
                    unit
                )
                (Value.IfThenElse ()
                    (eq "d" 4)
                    unit
                    unit
                )
            )
            [ [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = False }, BoolCondition { criterion = eq "c" 3, expectedValue = True } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = False }, BoolCondition { criterion = eq "c" 3, expectedValue = False } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = False }, BoolCondition { criterion = eq "b" 2, expectedValue = True }, BoolCondition { criterion = eq "c" 3, expectedValue = True } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = False }, BoolCondition { criterion = eq "b" 2, expectedValue = True }, BoolCondition { criterion = eq "c" 3, expectedValue = False } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = True }, BoolCondition { criterion = eq "c" 3, expectedValue = True } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = True }, BoolCondition { criterion = eq "c" 3, expectedValue = False } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = False }, BoolCondition { criterion = eq "b" 2, expectedValue = False }, BoolCondition { criterion = eq "d" 4, expectedValue = True } ]
            , [ BoolCondition { criterion = eq "a" 1, expectedValue = False }, BoolCondition { criterion = eq "b" 2, expectedValue = False }, BoolCondition { criterion = eq "d" 4, expectedValue = False } ]
            ]
        ]


assignTestCasesToBranchesTests : Test
assignTestCasesToBranchesTests =
    let
        ir =
            IR.empty

        assert : String -> Value.Definition () () -> List TestCase -> List ( Branch () (), List TestCase ) -> Test
        assert msg valueDef testCases expectedResult =
            test msg
                (\_ ->
                    BranchCoverage.assignTestCasesToBranches ir valueDef testCases
                        |> Expect.equal expectedResult
                )

        testCase : List Int -> TestCase
        testCase ints =
            TestCase (ints |> List.map (\int -> Just (Value.Literal () (WholeNumberLiteral int)))) unit ""
    in
    describe "assignTestCasesToBranches"
        [ assert "single if/else"
            { inputTypes = [ ( [ "a" ], (), intType () ) ]
            , outputType = Type.Unit ()
            , body =
                Value.IfThenElse ()
                    (eq "a" 1)
                    unit
                    unit
            }
            [ testCase [ 1 ]
            , testCase [ 2 ]
            , testCase [ 3 ]
            ]
            [ ( [ BoolCondition { criterion = eq "a" 1, expectedValue = True } ], [ testCase [ 1 ] ] )
            , ( [ BoolCondition { criterion = eq "a" 1, expectedValue = False } ], [ testCase [ 2 ], testCase [ 3 ] ] )
            ]
        , assert "nested if/else - two criteria - and"
            { inputTypes =
                [ ( [ "a" ], (), intType () )
                , ( [ "b" ], (), intType () )
                , ( [ "c" ], (), intType () )
                , ( [ "d" ], (), intType () )
                ]
            , outputType = Type.Unit ()
            , body =
                Value.IfThenElse ()
                    (and
                        (eq "a" 1)
                        (eq "b" 2)
                    )
                    (Value.IfThenElse ()
                        (eq "c" 3)
                        unit
                        unit
                    )
                    (Value.IfThenElse ()
                        (eq "d" 4)
                        unit
                        unit
                    )
            }
            [ testCase [ 1, 2, 3, 0 ]
            , testCase [ 1, 2, 4, 0 ]
            , testCase [ 1, 3, 0, 4 ]
            , testCase [ 1, 3, 0, 5 ]
            , testCase [ 2, 2, 0, 4 ]
            , testCase [ 2, 2, 0, 5 ]
            , testCase [ 2, 3, 0, 4 ]
            , testCase [ 2, 3, 0, 5 ]
            ]
            [ ( [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = True }, BoolCondition { criterion = eq "c" 3, expectedValue = True } ]
              , [ testCase [ 1, 2, 3, 0 ] ]
              )
            , ( [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = True }, BoolCondition { criterion = eq "c" 3, expectedValue = False } ]
              , [ testCase [ 1, 2, 4, 0 ] ]
              )
            , ( [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = False }, BoolCondition { criterion = eq "d" 4, expectedValue = True } ]
              , [ testCase [ 1, 3, 0, 4 ] ]
              )
            , ( [ BoolCondition { criterion = eq "a" 1, expectedValue = True }, BoolCondition { criterion = eq "b" 2, expectedValue = False }, BoolCondition { criterion = eq "d" 4, expectedValue = False } ]
              , [ testCase [ 1, 3, 0, 5 ] ]
              )
            , ( [ BoolCondition { criterion = eq "a" 1, expectedValue = False }, BoolCondition { criterion = eq "b" 2, expectedValue = True }, BoolCondition { criterion = eq "d" 4, expectedValue = True } ]
              , [ testCase [ 2, 2, 0, 4 ] ]
              )
            , ( [ BoolCondition { criterion = eq "a" 1, expectedValue = False }, BoolCondition { criterion = eq "b" 2, expectedValue = True }, BoolCondition { criterion = eq "d" 4, expectedValue = False } ]
              , [ testCase [ 2, 2, 0, 5 ] ]
              )
            , ( [ BoolCondition { criterion = eq "a" 1, expectedValue = False }, BoolCondition { criterion = eq "b" 2, expectedValue = False }, BoolCondition { criterion = eq "d" 4, expectedValue = True } ]
              , [ testCase [ 2, 3, 0, 4 ] ]
              )
            , ( [ BoolCondition { criterion = eq "a" 1, expectedValue = False }, BoolCondition { criterion = eq "b" 2, expectedValue = False }, BoolCondition { criterion = eq "d" 4, expectedValue = False } ]
              , [ testCase [ 2, 3, 0, 5 ] ]
              )
            ]
        ]


not : Value.Value () () -> Value.Value () ()
not a1 =
    apply (basics "not") a1


or : Value.Value () () -> Value.Value () () -> Value.Value () ()
or a1 a2 =
    apply2 (basics "or") a1 a2


and : Value.Value () () -> Value.Value () () -> Value.Value () ()
and a1 a2 =
    apply2 (basics "and") a1 a2


eq : String -> Int -> Value.Value () ()
eq varName val =
    apply2 (basics "equal") (var varName) (litInt val)
