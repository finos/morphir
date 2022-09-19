module Morphir.IR.ValueTests exposing (..)

import Dict
import Expect
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.SDK.String as String
import Morphir.IR.Value as Value exposing (Pattern(..), Value(..))
import Test exposing (Test, describe, test)


indexedMapValueTests : Test
indexedMapValueTests =
    let
        dummy index =
            Literal index (StringLiteral "dummy")

        dummyType =
            String.stringType ()
    in
    [ ( dummy 0, 0 )
    , ( Tuple 0 [ dummy 1, dummy 2, dummy 3 ], 3 )
    , ( List 0 [ dummy 1, dummy 2 ], 2 )
    , ( Record 0 <| Dict.fromList [ ( [ "field1" ], dummy 1 ), ( [ "field2" ], dummy 2 ), ( [ "field3" ], dummy 3 ) ], 3 )
    , ( LetDefinition 0 [ "foo" ] (Value.Definition [] (String.stringType ()) (dummy 1)) (dummy 2), 2 )
    , ( LetDefinition 0 [ "foo" ] (Value.Definition [ ( [ "arg1" ], 1, dummyType ), ( [ "arg2" ], 2, dummyType ) ] dummyType (dummy 3)) (dummy 4), 4 )
    , ( LetRecursion 0
            Dict.empty
            (dummy 1)
      , 1
      )
    , ( LetRecursion 0
            (Dict.fromList
                [ ( [ "foo" ], Value.Definition [ ( [ "arg1" ], 1, dummyType ), ( [ "arg2" ], 2, dummyType ) ] dummyType (dummy 3) )
                ]
            )
            (dummy 4)
      , 4
      )
    , ( LetRecursion 0
            (Dict.fromList
                [ ( [ "bar" ], Value.Definition [] dummyType (dummy 1) )
                , ( [ "foo" ], Value.Definition [ ( [ "arg1" ], 2, dummyType ), ( [ "arg2" ], 3, dummyType ) ] dummyType (dummy 4) )
                ]
            )
            (dummy 5)
      , 5
      )
    , ( LetRecursion 0
            (Dict.fromList
                [ ( [ "bar" ], Value.Definition [ ( [ "arg1" ], 1, dummyType ), ( [ "arg2" ], 2, dummyType ) ] dummyType (dummy 3) )
                , ( [ "foo" ], Value.Definition [] dummyType (dummy 4) )
                ]
            )
            (dummy 5)
      , 5
      )
    ]
        |> List.indexedMap
            (\index expectedOutput ->
                let
                    input =
                        expectedOutput
                            |> Tuple.first
                            |> Value.mapValueAttributes (always ()) (always ())
                in
                test ("case " ++ String.fromInt index) <|
                    \_ ->
                        Value.indexedMapValue (\i _ -> i) 0 input
                            |> Expect.equal expectedOutput
            )
        |> describe "indexedMapValue"


indexedMapPatternTests : Test
indexedMapPatternTests =
    [ ( WildcardPattern 0, 0 )
    , ( TuplePattern 0 [ WildcardPattern 1, WildcardPattern 2 ], 2 )
    , ( TuplePattern 0
            [ TuplePattern 1 [ WildcardPattern 2, WildcardPattern 3 ]
            , WildcardPattern 4
            ]
      , 4
      )
    ]
        |> List.indexedMap
            (\index expectedOutput ->
                let
                    input =
                        expectedOutput
                            |> Tuple.first
                            |> Value.mapPatternAttributes (always ())
                in
                test ("case " ++ String.fromInt index) <|
                    \_ ->
                        Value.indexedMapPattern (\i _ -> i) 0 input
                            |> Expect.equal expectedOutput
            )
        |> describe "indexedMapPattern"
