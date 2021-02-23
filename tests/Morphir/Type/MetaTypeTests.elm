module Morphir.Type.MetaTypeTests exposing (..)

import Expect
import Morphir.Type.MetaType as MetaType exposing (MetaType(..), Variable, variableByIndex)
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
    describe "substituteVariable"
        [ assert "simple replace"
            (MetaVar (variableByIndex 1))
            ( variableByIndex 1, MetaVar (variableByIndex 2) )
            (MetaVar (variableByIndex 2))
        , assert "no replace"
            (MetaVar (variableByIndex 2))
            ( variableByIndex 1, MetaVar (variableByIndex 3) )
            (MetaVar (variableByIndex 2))
        ]
