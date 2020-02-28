module Morphir.Elm.FrontendTests exposing (..)

import Dict
import Expect
import Morphir.DAG as DAG
import Morphir.Elm.Frontend as Frontend
import Set
import Test exposing (..)


frontendTest : Test
frontendTest =
    let
        moduleA =
            { path = "A.elm"
            , content =
                """
                module A exposing (..)
                   
                import B    
                """
            }

        moduleB =
            { path = "B.elm"
            , content =
                """
                module B exposing (..)
                   
                import A    
                """
            }

        dag =
            Dict.fromList
                [ ( [ "A" ], Set.fromList [ [ "B" ] ] )
                , ( [ "B" ], Set.fromList [ [ "A" ] ] )
                ]
                |> DAG.fromDict
    in
    test "first" <|
        \_ ->
            Frontend.initFromSource {} [ moduleA, moduleB ]
                |> Expect.equal (Err [ Frontend.CyclicModules dag ])
