module Morphir.SDK.DecimalTests exposing (..)

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
import Morphir.SDK.Decimal as Decimal exposing (..)
import Morphir.TestUtils exposing (expectFalse, expectTrue)
import Test exposing (..)


decimal : Fuzzer Decimal
decimal =
    float |> Fuzz.map Decimal.fromFloat


absTests : Test
absTests =
    describe "arithmetic operations"
        [ test "abs of negative value" <|
            \_ ->
                D.fromInt -42
                    |> Decimal.abs
                    |> Expect.equal (D.fromInt 42)
        , test "abs of positive value" <|
            \_ ->
                D.fromInt 42
                    |> Decimal.abs
                    |> Expect.equal (Decimal.fromInt 42)
        , test "abs of zero value" <|
            \_ ->
                D.fromInt 0
                    |> Decimal.abs
                    |> Expect.equal (Decimal.fromInt 0)
        ]


addTests : Test
addTests =
    describe "Decimal.add"
        [ fuzz2 int int "mirrors normal addition" <|
            \a b ->
                Expect.equal (Decimal.add (Decimal.fromInt a) (Decimal.fromInt b)) (Decimal.fromInt <| a + b)
        , fuzz2 decimal decimal "is commutative" <|
            \a b ->
                Expect.equal (Decimal.add a b) (Decimal.add b a)
        ]


subTests : Test
subTests =
    describe "Decimal.sub"
        [ fuzz2 int int "mirrors normal subtraction" <|
            \a b ->
                Expect.equal (Decimal.sub (Decimal.fromInt a) (Decimal.fromInt b)) (Decimal.fromInt <| a - b)
        , fuzz2 decimal decimal "switching orders is the same as the negation" <|
            \a b ->
                Expect.equal (Decimal.sub a b) (Decimal.negate (D.sub b a))
        ]


mulTests : Test
mulTests =
    let
        safeInt =
            intRange -46340 46340
    in
    describe "Decimal.mul"
        [ fuzz2 safeInt safeInt "mirrors normal multiplication" <|
            \a b ->
                expectTrue "Expected multiplication to mimic integer multiplication" <|
                    Decimal.eq (Decimal.mul (Decimal.fromInt a) (Decimal.fromInt b)) (Decimal.fromInt <| a * b)
        , fuzz2 decimal decimal "is commutative" <|
            \a b ->
                Expect.equal (Decimal.mul a b) (Decimal.mul b a)
        ]


constructionTests : Test
constructionTests =
    describe "construction tests"
        [ fuzz int "it should support construction from an Int" <|
            \n ->
                Decimal.fromInt n
                    |> Expect.equal (D.fromInt n)
        ]


fromStringTests : Test
fromStringTests =
    describe "Decimal.fromString"
        [ test "positive integer" <|
            \_ ->
                Expect.equal (Decimal.fromString "42") (Just <| Decimal.fromInt 42)
        , test "negative integer" <|
            \_ ->
                Expect.equal (Decimal.fromString "-21") (Just <| Decimal.fromInt -21)
        , test "zero" <|
            \_ ->
                Expect.equal (Decimal.fromString "0") (Just <| Decimal.fromInt 0)
        , test "non-number" <|
            \_ ->
                Expect.equal (Decimal.fromString "esdf") Nothing
        , test "decimal" <|
            \_ ->
                Expect.equal (Decimal.fromString "1.1") (Just <| D.fromFloat 1.1)
        ]


fromFloatTests : Test
fromFloatTests =
    describe "Decimal.fromFloat"
        [ test "positive float" <|
            \_ ->
                Expect.equal (Decimal.fromFloat 1) (Decimal.fromInt 1)
        , test "negative float" <|
            \_ ->
                Expect.equal (Decimal.fromFloat -1) (Decimal.fromInt -1)
        , test "zero" <|
            \_ ->
                Expect.equal (Decimal.fromFloat 0) (Decimal.fromInt 0)
        , test "decimal" <|
            \_ ->
                Expect.equal (Decimal.fromFloat 3.3) (Decimal.fromInt 33 |> Decimal.shiftDecimalLeft 1)
        , test "exponent" <|
            \_ ->
                Expect.equal (Decimal.fromFloat 1.1e0) (Decimal.fromInt 11 |> Decimal.shiftDecimalLeft 1)
        , fuzz niceFloat "equivalent to fromString" <|
            \a ->
                Expect.equal (Decimal.fromFloat a) ((Decimal.fromString <| String.fromFloat a) |> Maybe.withDefault Decimal.zero)
        ]


hundredTests : Test
hundredTests =
    describe "Decimal.hundred"
        [ test "positive integer" <|
            \_ ->
                Decimal.hundred 42 |> Decimal.toString |> Expect.equal (Decimal.fromInt 4200 |> Decimal.toString)
        , test "negative integer" <|
            \_ ->
                Decimal.hundred -2 |> Decimal.toString |> Expect.equal (Decimal.toString <| Decimal.fromInt -200)
        ]


thousandTests : Test
thousandTests =
    describe "Decimal.thousands"
        [ test "positive integer" <|
            \_ ->
                Decimal.thousand 4 |> Decimal.toString |> Expect.equal (Decimal.fromInt 4000 |> Decimal.toString)
        , test "negative integer" <|
            \_ ->
                Decimal.thousand -7 |> Decimal.toString |> Expect.equal (Decimal.toString <| Decimal.fromInt -7000)
        ]


millionTests : Test
millionTests =
    describe "Decimal.million"
        [ test "positive integer" <|
            \_ ->
                Decimal.million 21 |> Decimal.toString |> Expect.equal (Decimal.fromInt 21000000 |> Decimal.toString)
        , test "negative integer" <|
            \_ ->
                Decimal.million -99 |> Decimal.toString |> Expect.equal (Decimal.toString <| Decimal.fromInt -99000000)
        ]


tenthTests : Test
tenthTests =
    describe "Decimal.tenth"
        [ test "positive integer" <|
            \_ ->
                Decimal.tenth 1000 |> Expect.equal (Decimal.fromInt 100)
        , test "small positive integer" <|
            \_ ->
                Decimal.tenth 10 |> Expect.equal (Decimal.fromFloat 1.0)
        , test "negative integer" <|
            \_ ->
                Decimal.tenth -1000 |> Expect.equal (Decimal.fromFloat -100.0)
        , test "small negative integer" <|
            \_ ->
                Decimal.tenth -50 |> Expect.equal (Decimal.fromFloat -5.0)
        ]


hundredthTests : Test
hundredthTests =
    describe "Decimal.hundredth"
        [ test "positive integer" <|
            \_ ->
                Decimal.hundredth 100 |> Expect.equal (Decimal.fromFloat 1.0)
        , test "small positive integer" <|
            \_ ->
                Decimal.hundredth 10 |> Expect.equal (Decimal.fromFloat 0.1)
        , test "negative integer" <|
            \_ ->
                Decimal.hundredth -1000 |> Expect.equal (Decimal.fromFloat -10.0)
        , test "small negative integer" <|
            \_ ->
                Decimal.hundredth -50 |> Expect.equal (Decimal.fromFloat -0.5)
        ]


bpsTests : Test
bpsTests =
    describe "Decimal.bps"
        [ test "positive integer" <|
            \_ ->
                Decimal.bps 10001 |> Expect.equal (Decimal.fromFloat 1.0001)
        , test "small positive integer" <|
            \_ ->
                Decimal.bps 2 |> Decimal.toString |> Expect.equal "0.0002"
        , test "negative integer" <|
            \_ ->
                Decimal.bps -100001 |> Expect.equal (Decimal.fromFloat -10.0001)
        , test "small negative integer" <|
            \_ ->
                Decimal.bps -5 |> Expect.equal (Decimal.fromFloat -0.0005)
        ]


millionthTests : Test
millionthTests =
    describe "Decimal.millionth"
        [ test "positive integer" <|
            \_ ->
                Decimal.millionth 1000000 |> Expect.equal (Decimal.fromFloat 1.0)
        , test "negative integer" <|
            \_ ->
                Decimal.millionth -10000000 |> Expect.equal (Decimal.fromFloat -10.0)
        ]


toStringTests : Test
toStringTests =
    describe "Decimal.toString"
        [ test "positive" <|
            \_ ->
                Expect.equal "1" (Decimal.toString <| Decimal.fromInt 1)
        , test "zero" <|
            \_ ->
                Expect.equal "0" (Decimal.toString <| Decimal.fromInt 0)
        , test "negative" <|
            \_ ->
                Expect.equal "-1" (Decimal.toString <| Decimal.fromInt -1)
        , test "decimal" <|
            \_ ->
                Expect.equal "-1234.5678" (Decimal.toString <| D.fromFloat -1234.5678)
        ]


compareTests : Test
compareTests =
    describe "Decimal.compare"
        [ fuzz int "integer equality" <|
            \a ->
                Expect.equal EQ (Decimal.compare (Decimal.fromInt a) (Decimal.fromInt a))
        , fuzz int "integer less than" <|
            \a ->
                Expect.equal LT (Decimal.compare (Decimal.fromInt a) (Decimal.fromInt <| a + 1))
        , fuzz int "integer greater than" <|
            \a ->
                Expect.equal GT (Decimal.compare (Decimal.fromInt a) (Decimal.fromInt <| a - 1))
        ]


notEqualTests : Test
notEqualTests =
    describe "Decimal.neq"
        [ fuzz decimal "decimal inequality" <|
            \a ->
                expectTrue "Expected differing decimal values to not be equal" <|
                    Decimal.neq a (Decimal.add a Decimal.minusOne)
        , fuzz decimal "decimal equality" <|
            \a ->
                expectFalse "Expected the same value to be equal" <|
                    Decimal.neq a a
        ]


shiftDecimalLeftTests : Test
shiftDecimalLeftTests =
    describe "Decimal.shiftDecimalLeft"
        [ test "shift left for a whole number" <|
            \_ ->
                Decimal.fromInt 314
                    |> Decimal.shiftDecimalLeft 2
                    |> expectEqual (Decimal.fromFloat 3.14)
        , test "shift left for a decimal number" <|
            \_ ->
                Decimal.fromFloat 199.95
                    |> Decimal.shiftDecimalLeft 2
                    |> expectEqual (Decimal.fromFloat 1.9995)
        ]


shiftDecimalRightTests : Test
shiftDecimalRightTests =
    describe "Decimal.shiftDecimalRightTests"
        [ test "shift left for a whole number" <|
            \_ ->
                Decimal.fromInt 314
                    |> Decimal.shiftDecimalRight 3
                    |> expectEqual (Decimal.fromFloat 314000)
        , test "shift left for a decimal number" <|
            \_ ->
                Decimal.fromFloat 199.95
                    |> Decimal.shiftDecimalRight 1
                    |> expectEqual (Decimal.fromFloat 1999.5)
        ]


expectEqual : Decimal -> Decimal -> Expect.Expectation
expectEqual a b =
    if Decimal.eq a b then
        Expect.pass

    else
        [ Decimal.toString a, Decimal.toString b ] |> String.join " Expect.equal " |> Expect.fail
