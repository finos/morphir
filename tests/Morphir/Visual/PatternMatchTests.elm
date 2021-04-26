module Morphir.Visual.PatternMatchTests exposing (..)

import Element exposing (Attribute, Column, Element, fill, row, spacing, table, text, width)
import Expect
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Value as Value exposing (Pattern(..), Value(..))
import Morphir.Visual.ViewPatternMatch exposing (generateColumns, getDecomposedInput)
import Test exposing (..)


decomposedInputTests : Test
decomposedInputTests =
    describe "extraction of parameters in pattern match"
        [ test "test"
            (\_ ->
                getDecomposedInput Value.Variable |> Expect.equal []
            )
        ]


columnTests : Test
columnTests =
    describe "PatternMatch.columns"
        [ test "single"
            (\_ ->
                List.map .header
                    (generateColumns
                        (Value.Variable () [ "foo" ])
                        [ ( Value.WildcardPattern (), Value.Literal () (IntLiteral 1) ) ]
                    )
                    |> Expect.equal [ text "foo" ]
            )
        , test "2-elem tuple"
            (\_ ->
                List.map .header
                    (generateColumns
                        (Value.Tuple ()
                            [ Value.Variable () [ "foo" ]
                            , Value.Variable () [ "bar" ]
                            ]
                        )
                        [ ( Value.WildcardPattern (), Value.Literal () (IntLiteral 1) ) ]
                    )
                    |> Expect.equal [ text "foo", text "bar" ]
            )
        , test "3-elem tuple"
            (\_ ->
                List.map .header
                    (generateColumns
                        (Value.Tuple ()
                            [ Value.Variable () [ "foo" ]
                            , Value.Variable () [ "bar" ]
                            , Value.Variable () [ "baz" ]
                            ]
                        )
                        [ ( Value.WildcardPattern (), Value.Literal () (IntLiteral 1) ) ]
                    )
                    |> Expect.equal [ text "foo", text "bar", text "baz" ]
            )
        , test "multiple patterns"
            (\_ ->
                List.map .header
                    (generateColumns
                        (Value.Variable () [ "foo" ])
                        [ ( Value.LiteralPattern () (IntLiteral 1), Value.Literal () (IntLiteral 2) )
                        , ( Value.WildcardPattern (), Value.Literal () (IntLiteral 1) )
                        ]
                    )
                    |> Expect.equal [ text "foo" ]
            )
        ]
