module Morphir.Type.SolutionMapTests exposing (..)

import Dict
import Expect
import Morphir.Type.MetaType as MetaType exposing (MetaType(..), Variable, variable)
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
                [ ( variable 0, MetaVar (variable 1) )
                ]
            )
            ( variable 1, MetaVar (variable 2) )
            (SolutionMap.fromList
                [ ( variable 0, MetaVar (variable 2) )
                ]
            )
        , assert "substitute extensible record"
            (SolutionMap.fromList
                [ ( variable 0, MetaRecord (Just (variable 1)) (Dict.fromList [ ( [ "foo" ], MetaVar (variable 3) ) ]) )
                ]
            )
            ( variable 1, MetaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) (MetaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variable 3) ) ])) )
            (SolutionMap.fromList
                [ ( variable 0, MetaAlias ( [ [ "a" ] ], [ [ "b" ] ], [ "c" ] ) (MetaRecord Nothing (Dict.fromList [ ( [ "foo" ], MetaVar (variable 3) ) ])) )
                ]
            )
        ]
