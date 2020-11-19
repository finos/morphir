module Morphir.Value.InterpreterTests exposing (..)

import Dict
import Expect
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.SDK as SDK
import Morphir.IR.Value as Value
import Morphir.Value.Interpreter exposing (Reference(..), evaluate)
import Test exposing (Test, describe, test)


evaluateValueTests : Test
evaluateValueTests =
    let
        refs =
            SDK.nativeFunctions
                |> Dict.map
                    (\_ fun ->
                        NativeReference fun
                    )

        check desc input expectedOutput =
            test desc
                (\_ ->
                    evaluate refs input
                        |> Expect.equal
                            (Ok expectedOutput)
                )
    in
    describe "evaluateValue"
        [ check "True = True"
            (Value.Literal () (BoolLiteral True))
            (Value.Literal () (BoolLiteral True))
        , check "not True == False"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "not"))
                (Value.Literal () (BoolLiteral True))
            )
            (Value.Literal () (BoolLiteral False))
        , check "True && False == False"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "and"))
                    (Value.Literal () (BoolLiteral True))
                )
                (Value.Literal () (BoolLiteral False))
            )
            (Value.Literal () (BoolLiteral False))
        , check "False && True == False"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "and"))
                    (Value.Literal () (BoolLiteral False))
                )
                (Value.Literal () (BoolLiteral True))
            )
            (Value.Literal () (BoolLiteral False))
        ]
