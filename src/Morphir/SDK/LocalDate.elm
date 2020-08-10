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


module Morphir.SDK.LocalDate exposing  (LocalDate)

-- This is a temporary stub until we get into more requirements
type LocalDate = LocalDate



{-
module Morphir.SDK.LocalDate exposing  (Date, Month, Unit, fromCalendarDate, add)
    -- ( Date
    -- , Month, Weekday
    -- , today, fromPosix, fromCalendarDate, fromWeekDate, fromOrdinalDate, fromIsoString, fromRataDie
    -- , toIsoString, toRataDie
    -- , year, month, day, weekYear, weekNumber, weekday, ordinalDay, quarter, monthNumber, weekdayNumber
    -- , format
    -- , Language, formatWithLanguage
    -- , Unit(..), add, diff
    -- , Interval(..), ceiling, floor
    -- , range
    -- , compare, isBetween, min, max, clamp
    -- , monthToNumber, numberToMonth, weekdayToNumber, numberToWeekday
    -- )

{-| A `Date` is a representation of a day of the calendar without consideration for location.
    This module defines local date operations.

    @docs Date
-}

import Morphir.SDK.Int exposing (Int)
-- import Date exposing (Date, Month, Unit(..))
import Date


{-| Represents a date using the Rata Die system.

This has the advantage of making Date comparable since Int is comparable. 
-}
type alias Date =
    Date.Date


type alias Month =
    Date.Month

type alias Unit =
    Date.Unit


fromCalendarDate : Int -> Month -> Int -> Date
fromCalendarDate =
    Date.fromCalendarDate


-- Maths --
add : Unit -> Int -> Date -> Date
add = Date.add



-- year : Date -> Int
-- year ld =
--     Date.year ld


-- month : Date -> Int
-- month ld = 
--     native 
--         (ld 
--             |> Date.fromRataDie 
--             |> Date.monthNumber
--         )    


-- plusMonths : Int -> Date -> Date
-- plusMonths monthCount ld =
--     native
--         (ld 
--             |> Date.fromRataDie 
--             |> Date.add Date.Months monthCount 
--             |> Date.toRataDie
--         )


-- day : Date -> Int
-- day ld = 
--     native
--         (ld 
--             |> Date.fromRataDie 
--             |> Date.day
--         )  


-- plusDays : Int -> Date -> Date
-- plusDays dayCount ld =
--     native
--         (ld 
--             |> Date.fromRataDie 
--             |> Date.add Date.Days dayCount 
--             |> Date.toRataDie
--         )


-- diffInDays : Date -> Date -> Int
-- diffInDays ld1 ld2 = 
--     native
--         (Date.diff
--             Date.Days
--             (ld1 |> Date.fromRataDie)
--             (ld2 |> Date.fromRataDie)
--         )


-- type alias Month = 
--     Native Date.Month


-- lastDayOfMonth : Month -> Int -> Date
-- lastDayOfMonth m y = 
--     native
--         (Date.fromCalendarDate y m 1
--             |> Date.add Date.Months 1
--             |> Date.add Date.Days -1 
--             |> Date.toRataDie
--         )
-}
