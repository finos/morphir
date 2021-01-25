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
