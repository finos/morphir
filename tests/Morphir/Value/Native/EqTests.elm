module Morphir.Value.Native.EqTests exposing (..)

import Expect
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Value as Value
import Morphir.Value.Native.Eq as Eq
import Test exposing (Test, describe, test)


equalTests : Test
equalTests =
    let
        assert aValue bValue expectedResult =
            test (String.concat [ Value.toString aValue, " == ", Value.toString bValue ]) <|
                \_ ->
                    Eq.equal aValue bValue
                        |> Expect.equal expectedResult
    in
    describe "equal"
        [ assert (Value.Literal () (BoolLiteral True)) (Value.Literal () (BoolLiteral True)) (Ok True)
        , assert (Value.Literal () (BoolLiteral True)) (Value.Literal () (BoolLiteral False)) (Ok False)
        , assert
            (Value.Tuple () [ Value.Literal () (BoolLiteral True), Value.Literal () (BoolLiteral False) ])
            (Value.Tuple () [ Value.Literal () (BoolLiteral True), Value.Literal () (BoolLiteral False) ])
            (Ok True)
        , assert
            (Value.Tuple () [ Value.Literal () (BoolLiteral False), Value.Literal () (BoolLiteral False) ])
            (Value.Tuple () [ Value.Literal () (BoolLiteral True), Value.Literal () (BoolLiteral True) ])
            (Ok False)
        ]
