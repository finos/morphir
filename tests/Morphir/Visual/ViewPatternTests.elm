module Morphir.Visual.ViewPatternTests exposing (..)
import Elm.Syntax.Pattern exposing (Pattern(..))
import Morphir.IR.Value as Value exposing (Pattern(..))

import Morphir.Visual.ViewPattern as ViewPattern exposing (..)
import Expect
import Test exposing (..)

wildCardPatternTests : Test
wildCardPatternTests =
    describe "Wildcard Pattern"
        [ test "empty output" <|
            \_ ->
                ViewPattern.patternAsText (Value.WildcardPattern ())
                    |> Expect.equal "_"
        ]

asPatternWildCardTests : Test
asPatternWildCardTests =
    describe "AsPattern w/ Wildcard Pattern with integers"
            [ test "empty" <|
               \_ ->
                   ViewPattern.patternAsText (Value.AsPattern 0
                   (Value.WildcardPattern 0) [])
                      |> Expect.equal ""

              , test "result of 'five'" <|
                \_ ->
                    ViewPattern.patternAsText (Value.AsPattern 5 (Value.WildcardPattern 5) ["five"])
                        |> Expect.equal "five"
            ]

asPatternTests : Test
asPatternTests =
    describe "AsPattern"
            [ test "empty" <|
               \_ ->
                   ViewPattern.patternAsText (Value.AsPattern "" (WildcardPattern "") [])
                      |> Expect.equal ""

              , test "result of 'five'" <|
                \_ ->
                    ViewPattern.patternAsText (Value.AsPattern 5
                     (Value.AsPattern 5 (Value.WildcardPattern 5) ["five"]) ["ten"])
                        |> Expect.equal "five as ten"
            ]