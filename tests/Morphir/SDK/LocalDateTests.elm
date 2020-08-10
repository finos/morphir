{-
Copyright 2020 Morgan Stanley

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


module Morphir.SDK.LocalDateTests exposing (..)

import Expect
import Test exposing (..)

import Morphir.SDK.LocalDate

ld = 1

{- 
import Time exposing (Month(..))
import Date exposing (Unit(..))


mathTests : Test
mathTests =
    describe "date maths"
        [ test "add day" <|
            \_ ->
                (LocalDate.fromCalendarDate 2020 Jan 1) 
                    |> LocalDate.add Months 1
                    |> Expect.equal (LocalDate.fromCalendarDate 2020 Feb 1)
        ]
-}
