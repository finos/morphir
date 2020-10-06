module Morphir.IR.ValueTests exposing (..)

import Expect
import Morphir.IR.Value as Value exposing (Pattern(..))
import Test exposing (Test, describe, test)


indexedMapPatternTests : Test
indexedMapPatternTests =
    [ ( WildcardPattern (), ( WildcardPattern 0, 0 ) )
    , ( TuplePattern () [ WildcardPattern (), WildcardPattern () ]
      , ( TuplePattern 0 [ WildcardPattern 1, WildcardPattern 2 ], 2 )
      )
    , ( TuplePattern ()
            [ TuplePattern () [ WildcardPattern (), WildcardPattern () ]
            , WildcardPattern ()
            ]
      , ( TuplePattern 0
            [ TuplePattern 1 [ WildcardPattern 2, WildcardPattern 3 ]
            , WildcardPattern 4
            ]
        , 4
        )
      )
    ]
        |> List.indexedMap
            (\index ( input, expectedOutput ) ->
                test ("case " ++ String.fromInt index) <|
                    \_ ->
                        Value.indexedMapPattern (\i _ -> i) 0 input
                            |> Expect.equal expectedOutput
            )
        |> describe "indexedMapPattern"
