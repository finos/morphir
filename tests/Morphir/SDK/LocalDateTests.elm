module Morphir.SDK.LocalDateTests exposing (..)

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

import Date as Date exposing (Unit(..), add, fromCalendarDate)
import Expect
import Morphir.SDK.LocalDate as LocalDate exposing (..)
import Test exposing (..)
import Time exposing (Month(..))


mathTests : Test
mathTests =
    describe "date maths"
        [ test "add day" <|
            \_ ->
                Date.fromCalendarDate 2020 Jan 1
                    |> LocalDate.addDays 1
                    |> Expect.equal (Date.fromCalendarDate 2020 Jan 2)
        , test "subtract day" <|
            \_ ->
                Date.fromCalendarDate 2020 Jan 2
                    |> LocalDate.addDays -1
                    |> Expect.equal (Date.fromCalendarDate 2020 Jan 1)
        , test "add week" <|
            \_ ->
                Date.fromCalendarDate 2020 Jan 7
                    |> LocalDate.addWeeks 1
                    |> Expect.equal (Date.fromCalendarDate 2020 Jan 14)
        , test "subtract week" <|
            \_ ->
                Date.fromCalendarDate 2020 Jan 14
                    |> LocalDate.addWeeks -1
                    |> Expect.equal (Date.fromCalendarDate 2020 Jan 7)
        , test "add month" <|
            \_ ->
                Date.fromCalendarDate 2020 Jan 1
                    |> LocalDate.addMonths 1
                    |> Expect.equal (Date.fromCalendarDate 2020 Feb 1)
        , test "subtract month" <|
            \_ ->
                Date.fromCalendarDate 2020 Feb 1
                    |> LocalDate.addMonths -1
                    |> Expect.equal (Date.fromCalendarDate 2020 Jan 1)
        , test "add year" <|
            \_ ->
                Date.fromCalendarDate 2020 Jan 1
                    |> LocalDate.addYears 1
                    |> Expect.equal (Date.fromCalendarDate 2021 Jan 1)
        , test "subtract year" <|
            \_ ->
                Date.fromCalendarDate 2020 Feb 1
                    |> LocalDate.addYears -1
                    |> Expect.equal (Date.fromCalendarDate 2019 Feb 1)
        , test "fromISO string to localDate" <|
            \_ ->
                LocalDate.fromISO "2023-06-13"
                    |> Maybe.withDefault (Date.fromCalendarDate 2019 Feb 1)
                    |> Expect.equal (Date.fromCalendarDate 2023 Jun 13)
        , test "toISOString" <|
            \_ ->
                Date.fromCalendarDate 2023 Jun 13
                    |> LocalDate.toISOString
                    |> Expect.equal "2023-06-13"
        , test "fromParts" <|
            \_ ->
                LocalDate.fromParts 2023 6 9
                    |> Maybe.withDefault (Date.fromCalendarDate 2019 Feb 1)
                    |> Expect.equal (Date.fromCalendarDate 2023 Jun 9)
        , test "diffInDays" <|
            \_ ->
                Date.fromCalendarDate 2023 Jun 19
                    |> LocalDate.diffInDays (Date.fromCalendarDate 2023 Jun 9)
                    |> Expect.equal 10
        , test "diffInWeeks" <|
            \_ ->
                Date.fromCalendarDate 2023 Jun 19
                    |> LocalDate.diffInWeeks (Date.fromCalendarDate 2023 Jun 9)
                    |> Expect.equal 1
        , test "diffInMonths" <|
            \_ ->
                Date.fromCalendarDate 2023 Jun 19
                    |> LocalDate.diffInMonths (Date.fromCalendarDate 2023 Jun 9)
                    |> Expect.equal 0
        , test "diffInYears" <|
            \_ ->
                Date.fromCalendarDate 2024 Jun 19
                    |> LocalDate.diffInYears (Date.fromCalendarDate 2023 Jun 9)
                    |> Expect.equal 1
        ]


constructorTests : Test
constructorTests =
    describe "constructor tests"
        [ test "valid fromISO" <|
            \_ ->
                LocalDate.fromISO "2020-01-01"
                    |> Expect.equal (Date.fromIsoString "2020-01-01" |> Result.toMaybe)
        , test "invalid fromISO parsing" <|
            \_ ->
                LocalDate.fromISO "2020-01 hello"
                    |> Expect.equal Nothing
        , test "invalid fromISO numeric" <|
            \_ ->
                LocalDate.fromISO "2020-01-55"
                    |> Expect.equal Nothing
        , test "valid fromParts" <|
            \_ ->
                LocalDate.fromParts 2020 1 1
                    |> Expect.equal (Just (Date.fromCalendarDate 2020 Jan 1))
        , test "invalid month fromParts" <|
            \_ ->
                LocalDate.fromParts 2020 13 1
                    |> Expect.equal Nothing
        , test "invalid day fromParts" <|
            \_ ->
                LocalDate.fromParts 2020 2 30
                    |> Expect.equal Nothing
        , test "valid fromCalendarDate" <|
            \_ ->
                LocalDate.fromCalendarDate 2023 December 25
                    |> Expect.equal (Date.fromCalendarDate 2023 Dec 25)
        , test "invalid but pinned fromCalendarDate" <|
            \_ ->
                LocalDate.fromCalendarDate 2023 December 39
                    |> Expect.equal (Date.fromCalendarDate 2023 Dec 31)
        , test "valid fromOrdinalDate" <|
            \_ ->
                LocalDate.fromOrdinalDate 2023 15
                    |> Expect.equal (Date.fromCalendarDate 2023 Jan 15)
        ]
