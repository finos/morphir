module Morphir.Type.MetaTypeTests exposing (..)

import Expect
import Morphir.Type.MetaType as MetaType exposing (MetaType(..))
import Morphir.Type.MetaVar exposing (Variable, variable)
import Test exposing (Test, describe, test)


substituteVariableTests : Test
substituteVariableTests =
    let
        assert : String -> MetaType -> ( Variable, MetaType ) -> MetaType -> Test
        assert msg original ( var, replacement ) expected =
            test msg
                (\_ ->
                    original
                        |> MetaType.substituteVariable var replacement
                        |> Expect.equal expected
                )
    in
    describe "addSolution"
        [ assert "simple replace"
            (MetaVar (variable 1))
            ( variable 1, MetaVar (variable 2) )
            (MetaVar (variable 2))
        , assert "no replace"
            (MetaVar (variable 2))
            ( variable 1, MetaVar (variable 3) )
            (MetaVar (variable 2))
        ]
