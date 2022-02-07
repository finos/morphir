module Morphir.SDK.LocalTimeTests exposing (..)

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

import Expect
import Morphir.SDK.LocalTime as LocalTime exposing (..)
import Test exposing (..)
import Time exposing (toHour, toMinute, toSecond, utc)


mathTests : Test
mathTests =
    describe "time maths"
        [ test "add hours" <|
            \_ ->
                addHours 1
                    (Maybe.withDefault (fromMilliseconds 0) <|
                        fromISO "2022-01-28T12:56:30"
                    )
                    |> toHour utc
                    |> Expect.equal 13
        , test "substract hours" <|
            \_ ->
                addHours -1
                    (Maybe.withDefault (fromMilliseconds 0) <|
                        fromISO "2022-01-28T12:56:30"
                    )
                    |> toHour utc
                    |> Expect.equal 11
        , test "add minutes" <|
            \_ ->
                addMinutes 1
                    (Maybe.withDefault (fromMilliseconds 0) <|
                        fromISO "2022-01-28T12:56:30"
                    )
                    |> toMinute utc
                    |> Expect.equal 57
        , test "substract minutes" <|
            \_ ->
                addMinutes -1
                    (Maybe.withDefault (fromMilliseconds 0) <|
                        fromISO "2022-01-28T12:56:30"
                    )
                    |> toMinute utc
                    |> Expect.equal 55
        , test "add seconds" <|
            \_ ->
                addSeconds 1
                    (Maybe.withDefault (fromMilliseconds 0) <|
                        fromISO "2022-01-28T12:56:30"
                    )
                    |> toSecond utc
                    |> Expect.equal 31
        , test "substract seconds" <|
            \_ ->
                addSeconds -1
                    (Maybe.withDefault (fromMilliseconds 0) <|
                        fromISO "2022-01-28T12:56:30"
                    )
                    |> toSecond utc
                    |> Expect.equal 29
        , test "diffInMinutes" <|
            \_ ->
                diffInMinutes
                    (Maybe.withDefault (fromMilliseconds 0) <|
                        fromISO "2022-01-28T13:49:30"
                    )
                    (Maybe.withDefault (fromMilliseconds 0) <|
                        fromISO "2022-01-28T12:56:30"
                    )
                    |> Expect.equal 53
        , test "diffInHours less than an hour elapsed" <|
            \_ ->
                diffInHours
                    (Maybe.withDefault (fromMilliseconds 0) <|
                        fromISO "2022-01-28T13:49:30"
                    )
                    (Maybe.withDefault (fromMilliseconds 0) <|
                        fromISO "2022-01-28T12:56:30"
                    )
                    |> Expect.equal 0
        , test "diffInHours more than an hour elapsed" <|
            \_ ->
                diffInHours
                    (Maybe.withDefault (fromMilliseconds 0) <|
                        fromISO "2022-01-28T15:49:30"
                    )
                    (Maybe.withDefault (fromMilliseconds 0) <|
                        fromISO "2022-01-28T12:56:30"
                    )
                    |> Expect.equal 2
        , test "diffInSeconds" <|
            \_ ->
                diffInSeconds
                    (Maybe.withDefault (fromMilliseconds 0) <|
                        fromISO "2022-01-28T12:58:30"
                    )
                    (Maybe.withDefault (fromMilliseconds 0) <|
                        fromISO "2022-01-28T12:56:30"
                    )
                    |> Expect.equal 120
        ]


constructorTests : Test
constructorTests =
    describe "constructor tests"
        [ test "valid fromIso" <|
            \_ ->
                fromISO "2022-01-28T12:56:30"
                    |> Expect.equal (Just (Time.millisToPosix 1643374590000))
        , test "invalid fromISO parsing" <|
            \_ ->
                fromISO "2022-01-28TTTTT"
                    |> Expect.equal Nothing
        , test "invalid fromISO numeric" <|
            \_ ->
                fromISO "12:56:30"
                    |> Expect.equal Nothing
        , test "fromMilliseconds" <|
            \_ ->
                fromMilliseconds 0
                    |> Expect.equal (Time.millisToPosix 0)
        ]
