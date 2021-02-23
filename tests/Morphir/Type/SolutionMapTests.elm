module Morphir.Type.SolutionMapTests exposing (..)

import Dict
import Expect
import Morphir.Type.MetaType as MetaType exposing (MetaType(..), Variable, variableByIndex)
import Morphir.Type.SolutionMap as SolutionMap exposing (SolutionMap)
import Test exposing (Test, describe, test)


substituteVariableTests : Test
substituteVariableTests =
    let
        assert : String -> SolutionMap -> ( Variable, MetaType ) -> SolutionMap -> Test
        assert msg original ( var, replacement ) expected =
            test msg
                (\_ ->
                    original
                        |> SolutionMap.substituteVariable var replacement
                        |> Expect.equal expected
                )
    in
    describe "substituteVariable"
        [ assert "substitute variable"
            (SolutionMap.fromList
                [ ( variableByIndex 0, MetaVar (variableByIndex 1) )
                ]
            )
            ( variableByIndex 1, MetaVar (variableByIndex 2) )
            (SolutionMap.fromList
                [ ( variableByIndex 0, MetaVar (variableByIndex 2) )
                ]
            )
        , assert "substitute extensible record"
            (SolutionMap.fromList
                [ ( variableByIndex 0, MetaRecord (Just (variableByIndex 1)) (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ]) )
                ]
            )
            ( variableByIndex 1, MetaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) (MetaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
            (SolutionMap.fromList
                [ ( variableByIndex 0, MetaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) (MetaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variableByIndex 3) ) ])) )
                ]
            )
        ]
