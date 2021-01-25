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
import Morphir.SDK.Decimal as Decimal exposing (..)
import Morphir.SDK.Number as Number exposing (Number)
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



--absTests : Test
--absTests =
--    describe "arithmetic operations"
--        [ test "abs of negative value" <|
--            \_ ->
--                D.fromInt -42
--                    |> Decimal.abs
--                    |> Expect.equal (D.fromInt 42)
--        , test "abs of positive value" <|
--            \_ ->
--                D.fromInt 42
--                    |> Decimal.abs
--                    |> Expect.equal (Decimal.fromInt 42)
--        , test "abs of zero value" <|
--            \_ ->
--                D.fromInt 0
--                    |> Decimal.abs
--                    |> Expect.equal (Decimal.fromInt 0)
--        ]
--
--
--addTests : Test
--addTests =
--    describe "Number.add"
--        [ fuzz2 int int "mirrors normal addition" <|
--            \a b ->
--                Expect.equal (Number.add (Decimal.fromInt a) (Decimal.fromInt b)) (Decimal.fromInt <| a + b)
--        , fuzz2 number number "is commutative" <|
--            \a b ->
--                Expect.equal (Decimal.add a b) (Decimal.add b a)
--        ]
--
--
--subTests : Test
--subTests =
--    describe "Decimal.sub"
--        [ fuzz2 int int "mirrors normal subtraction" <|
--            \a b ->
--                Expect.equal (Decimal.sub (Decimal.fromInt a) (Decimal.fromInt b)) (Decimal.fromInt <| a - b)
--        , fuzz2 number number "switching orders is the same as the negation" <|
--            \a b ->
--                Expect.equal (Decimal.sub a b) (Decimal.negate (D.sub b a))
--        ]
--
--
--mulTests : Test
--mulTests =
--    let
--        safeInt =
--            intRange -46340 46340
--    in
--    describe "Decimal.mul"
--        [ fuzz2 safeInt safeInt "mirrors normal multiplication" <|
--            \a b ->
--                Expect.true "Expected multiplication to mimic integer multiplication" <|
--                    Decimal.eq (Decimal.mul (Decimal.fromInt a) (Decimal.fromInt b)) (Decimal.fromInt <| a * b)
--        , fuzz2 number number "is commutative" <|
--            \a b ->
--                Expect.equal (Decimal.mul a b) (Decimal.mul b a)
--        ]
--
--
--constructionTests : Test
--constructionTests =
--    describe "construction tests"
--        [ fuzz int "it should support construction from an Int" <|
--            \n ->
--                Decimal.fromInt n
--                    |> Expect.equal (D.fromInt n)
--        ]
--
--
--fromStringTests : Test
--fromStringTests =
--    describe "Decimal.fromString"
--        [ test "positive integer" <|
--            \_ ->
--                Expect.equal (Decimal.fromString "42") (Just <| Decimal.fromInt 42)
--        , test "negative integer" <|
--            \_ ->
--                Expect.equal (Decimal.fromString "-21") (Just <| Decimal.fromInt -21)
--        , test "zero" <|
--            \_ ->
--                Expect.equal (Decimal.fromString "0") (Just <| Decimal.fromInt 0)
--        , test "non-number" <|
--            \_ ->
--                Expect.equal (Decimal.fromString "esdf") Nothing
--        , fuzz2 int int "exponent" <|
--            \a b ->
--                Expect.equal (Decimal.fromString <| String.fromInt a ++ "e" ++ String.fromInt b)
--                    (Just <| D.fromIntWithExponent a b)
--        , test "decimal" <|
--            \_ ->
--                Expect.equal (Decimal.fromString "1.1") (Just <| D.fromIntWithExponent 11 -1)
--        ]
--
--
--fromFloatTests : Test
--fromFloatTests =
--    describe "Decimal.fromFloat"
--        [ test "positive float" <|
--            \_ ->
--                Expect.equal (Decimal.fromFloat 1) (Just <| Decimal.fromInt 1)
--        , test "negative float" <|
--            \_ ->
--                Expect.equal (Decimal.fromFloat -1) (Just <| Decimal.fromInt -1)
--        , test "zero" <|
--            \_ ->
--                Expect.equal (Decimal.fromFloat 0) (Just <| Decimal.fromInt 0)
--        , test "decimal" <|
--            \_ ->
--                Expect.equal (Decimal.fromFloat 3.3) (Decimal.fromString "3.3")
--        , test "exponent" <|
--            \_ ->
--                Expect.equal (Decimal.fromFloat 1.1e0) (Decimal.fromString "1.1e0")
--        , fuzz float "equivalent to fromString" <|
--            \a ->
--                Expect.equal (Decimal.fromFloat a) (Decimal.fromString <| String.fromFloat a)
--        ]
--
--
--hundredTests : Test
--hundredTests =
--    describe "Decimal.hundred"
--        [ test "positive integer" <|
--            \_ ->
--                Decimal.hundred 42 |> Decimal.toString |> Expect.equal (Decimal.fromInt 4200 |> Decimal.toString)
--        , test "negative integer" <|
--            \_ ->
--                Decimal.hundred -2 |> Decimal.toString |> Expect.equal (Decimal.toString <| Decimal.fromInt -200)
--        ]
--
--
--thousandTests : Test
--thousandTests =
--    describe "Decimal.thousands"
--        [ test "positive integer" <|
--            \_ ->
--                Decimal.thousand 4 |> Decimal.toString |> Expect.equal (Decimal.fromInt 4000 |> Decimal.toString)
--        , test "negative integer" <|
--            \_ ->
--                Decimal.thousand -7 |> Decimal.toString |> Expect.equal (Decimal.toString <| Decimal.fromInt -7000)
--        ]
--
--
--millionTests : Test
--millionTests =
--    describe "Decimal.million"
--        [ test "positive integer" <|
--            \_ ->
--                Decimal.million 21 |> Decimal.toString |> Expect.equal (Decimal.fromInt 21000000 |> Decimal.toString)
--        , test "negative integer" <|
--            \_ ->
--                Decimal.million -99 |> Decimal.toString |> Expect.equal (Decimal.toString <| Decimal.fromInt -99000000)
--        ]
--
--
--tenthTests : Test
--tenthTests =
--    describe "Decimal.tenth"
--        [ test "positive integer" <|
--            \_ ->
--                Decimal.tenth 1000 |> Decimal.toString |> Expect.equal "100.0"
--        , test "small positive integer" <|
--            \_ ->
--                Decimal.tenth 10 |> Decimal.toString |> Expect.equal "1.0"
--        , test "negative integer" <|
--            \_ ->
--                Decimal.tenth -1000 |> Decimal.toString |> Expect.equal "-100.0"
--        , test "small negative integer" <|
--            \_ ->
--                Decimal.tenth -50 |> Decimal.toString |> Expect.equal "-5.0"
--        ]
--
--
--hundredthTests : Test
--hundredthTests =
--    describe "Decimal.hundredth"
--        [ test "positive integer" <|
--            \_ ->
--                Decimal.hundredth 100 |> Decimal.toString |> Expect.equal "1.00"
--        , test "small positive integer" <|
--            \_ ->
--                Decimal.hundredth 10 |> Decimal.toString |> Expect.equal "0.10"
--        , test "negative integer" <|
--            \_ ->
--                Decimal.hundredth -1000 |> Decimal.toString |> Expect.equal "-10.00"
--        , test "small negative integer" <|
--            \_ ->
--                Decimal.hundredth -50 |> Decimal.toString |> Expect.equal "-0.50"
--        ]
--
--
--bpsTests : Test
--bpsTests =
--    describe "Decimal.bps"
--        [ test "positive integer" <|
--            \_ ->
--                Decimal.bps 10000 |> Decimal.toString |> Expect.equal "1.0000"
--        , test "small positive integer" <|
--            \_ ->
--                Decimal.bps 2 |> Decimal.toString |> Expect.equal "0.0002"
--        , test "negative integer" <|
--            \_ ->
--                Decimal.bps -100000 |> Decimal.toString |> Expect.equal "-10.0000"
--        , test "small negative integer" <|
--            \_ ->
--                Decimal.bps -5 |> Decimal.toString |> Expect.equal "-0.0005"
--        ]
--
--
--millionthTests : Test
--millionthTests =
--    describe "Decimal.millionth"
--        [ test "positive integer" <|
--            \_ ->
--                Decimal.millionth 1000000 |> Decimal.toString |> Expect.equal "1.000000"
--        , test "negative integer" <|
--            \_ ->
--                Decimal.millionth -10000000 |> Decimal.toString |> Expect.equal "-10.000000"
--        ]
--
--
--toStringTests : Test
--toStringTests =
--    describe "Decimal.toString"
--        [ test "positive" <|
--            \_ ->
--                Expect.equal "1" (Decimal.toString <| Decimal.fromInt 1)
--        , test "zero" <|
--            \_ ->
--                Expect.equal "0" (Decimal.toString <| Decimal.fromInt 0)
--        , test "negative" <|
--            \_ ->
--                Expect.equal "-1" (Decimal.toString <| Decimal.fromInt -1)
--        , test "decimal" <|
--            \_ ->
--                Expect.equal "-1234.5678" (Decimal.toString <| D.fromIntWithExponent -12345678 -4)
--        ]
--
--
--compareTests : Test
--compareTests =
--    describe "Decimal.compare"
--        [ fuzz int "integer equality" <|
--            \a ->
--                Expect.equal EQ (Decimal.compare (Decimal.fromInt a) (Decimal.fromInt a))
--        , fuzz int "integer less than" <|
--            \a ->
--                Expect.equal LT (Decimal.compare (Decimal.fromInt a) (Decimal.fromInt <| a + 1))
--        , fuzz int "integer greater than" <|
--            \a ->
--                Expect.equal GT (Decimal.compare (Decimal.fromInt a) (Decimal.fromInt <| a - 1))
--        ]


equalTests : Test
equalTests =
    describe "Number.equal"
        [ fuzz number "number inequality" <|
            \a ->
                Expect.false "Expected differing number values to not be equal" <|
                    Number.equal a (Number.add a (Number.fromInt 1))
        , fuzz number "number equality" <|
            \a ->
                Expect.true "Expected the same value to be equal" <|
                    Number.equal a a
        ]


notEqualTests : Test
notEqualTests =
    describe "Number.notEqual"
        [ fuzz number "number inequality" <|
            \a ->
                Expect.true "Expected differing number values to not be equal" <|
                    Number.notEqual a (Number.add a (Number.fromInt 1))
        , fuzz number "number equality" <|
            \a ->
                Expect.false "Expected the same value to be equal" <|
                    Number.notEqual a a
        ]
