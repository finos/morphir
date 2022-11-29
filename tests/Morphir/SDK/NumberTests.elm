module Morphir.SDK.NumberTests exposing (..)

{-
   Copyright 2021 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}

import Decimal as D
import Expect
import Fuzz exposing (..)
import Morphir.FuzzEx exposing (..)
import Morphir.SDK.Number as Number exposing (Number)
import Morphir.TestUtils exposing (expectFalse, expectTrue)
import Test exposing (..)


number : Fuzzer Number
number =
    Fuzz.map2
        (\nom denom ->
            Number.divide (Number.fromInt nom) (Number.fromInt denom)
                |> Result.withDefault Number.zero
        )
        int
        int


over : Int -> Int -> Number
over d n =
    makeNumber n d


makeNumber : Int -> Int -> Number
makeNumber n d =
    let
        numerator =
            Number.fromInt n

        denominator =
            Number.fromInt d
    in
    Number.divide numerator denominator |> Result.withDefault Number.zero


equalTests : Test
equalTests =
    describe "Number.equal"
        [ fuzz number "number inequality" <|
            \a ->
                expectFalse "Expected differing number values to not be equal" <|
                    Number.equal a (Number.add a (Number.fromInt 1))
        , fuzz number "number equality" <|
            \a ->
                expectTrue "Expected the same value to be equal" <|
                    Number.equal a a
        ]


notEqualTests : Test
notEqualTests =
    describe "Number.notEqual"
        [ fuzz number "number inequality" <|
            \a ->
                expectTrue "Expected differing number values to not be equal" <|
                    Number.notEqual a (Number.add a (Number.fromInt 1))
        , fuzz number "number equality" <|
            \a ->
                expectFalse "Expected the same value to be equal" <|
                    Number.notEqual a a
        ]


divideTests : Test
divideTests =
    describe "Number.divide"
        [ test "dividing by zero should result in DivisionByZero" <|
            \_ ->
                case Number.divide (Number.fromInt 42) (Number.fromInt 0) of
                    Err _ ->
                        Expect.pass

                    Ok res ->
                        "Expected to fail with DivisionByZero error, but it didn't, we received the value of "
                            ++ Number.toFractionalString res
                            ++ " instead."
                            |> Expect.fail
        , fuzz nonZeroInt "dividing a non-zero number by itself should equal 1" <|
            \n ->
                Number.divide
                    (Number.fromInt n)
                    (Number.fromInt n)
                    |> expectNumberResultEqual Number.one
        ]


simplifyTests : Test
simplifyTests =
    describe "Number.simplify"
        [ test "4/2 should reduce to 2/1" <|
            \_ ->
                case Number.simplify (4 |> over 2) of
                    Nothing ->
                        Expect.fail "expected simplification to occur but it didn't"

                    Just result ->
                        result |> expectNumbersEqual (Number.fromInt 2)
        , test "7/5 should not simplify" <|
            \_ ->
                case Number.simplify (7 |> over 5) of
                    Nothing ->
                        Expect.pass

                    Just result ->
                        if Number.isSimplified result then
                            Expect.pass

                        else
                            Number.toFractionalString result
                                |> (++) "Expected no simplification to occur but the number simplified to "
                                |> Expect.fail
        , fuzz (intRange 2 999) "simplifying with a numerator of zero" <|
            \n ->
                case Number.simplify (0 |> over n) of
                    Nothing ->
                        Expect.fail "Expected simplification to occur but it didn't"

                    Just actualValue ->
                        actualValue |> expectNumbersEqual Number.zero
        ]


expectNumberResultEqual : Number -> Result error Number -> Expect.Expectation
expectNumberResultEqual expected value =
    case value of
        Ok actual ->
            expectNumbersEqual expected actual

        Err _ ->
            Expect.fail "Expected numbers to be equal but the given result was an error"


expectNumbersEqual : Number -> Number -> Expect.Expectation
expectNumbersEqual a b =
    if Number.equal a b then
        Expect.pass

    else
        [ "Expected ", Number.toFractionalString a, "to equal", Number.toFractionalString b ] |> String.join " " |> Expect.fail
