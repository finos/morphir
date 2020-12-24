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


module Morphir.SDK.LocalDate exposing
    ( LocalDate
    , diffInDays, diffInWeeks, diffInMonths, diffInYears
    , addDays, addWeeks, addMonths, addYears
    , fromISO, fromParts
    )

{-| This module adds the definition of a date without time zones. Useful in business modeling.

@docs LocalDate
@docs diffInDays, diffInWeeks, diffInMonths, diffInYears
@docs addDays, addWeeks, addMonths, addYears

-}

import Date exposing (Date, Unit(..))


{-| Concept of a date without time zones.
-}
type alias LocalDate =
    Date


{-| Find the number of days between the given dates.
-}
diffInDays : LocalDate -> LocalDate -> Int
diffInDays fromDate toDate =
    Date.diff Days fromDate toDate


{-| Find the number of weeks between the given dates.
-}
diffInWeeks : LocalDate -> LocalDate -> Int
diffInWeeks fromDate toDate =
    Date.diff Weeks fromDate toDate


{-| Find the number of months between the given dates.
-}
diffInMonths : LocalDate -> LocalDate -> Int
diffInMonths fromDate toDate =
    Date.diff Months fromDate toDate


{-| Find the number of years between the given dates.
-}
diffInYears : LocalDate -> LocalDate -> Int
diffInYears fromDate toDate =
    Date.diff Years fromDate toDate


{-| Add the given days to a given date.
-}
addDays : Int -> LocalDate -> LocalDate
addDays count date =
    Date.add Days count date


{-| Add the given weeks to a given date.
-}
addWeeks : Int -> LocalDate -> LocalDate
addWeeks count date =
    Date.add Weeks count date


{-| Add the given months to a given date.
-}
addMonths : Int -> LocalDate -> LocalDate
addMonths count date =
    Date.add Months count date


{-| Add the given years to a given date.
-}
addYears : Int -> LocalDate -> LocalDate
addYears count date =
    Date.add Years count date


{-| Construct a LocalDate based on ISO formatted string. Opportunity for error denoted by Maybe return type.
-}
fromISO : String -> Maybe LocalDate
fromISO iso =
    Date.fromIsoString iso |> Result.toMaybe


{-| Construct a LocalDate based on Year, Month, Day. Opportunity for error denoted by Maybe return type.
Errors can occur when any of the given values fall outside of their relevant constraints.
For example, the date given as 2000 2 30 (2000-Feb-30) would fail because the day of the 30th is impossible.
-}
fromParts : Int -> Int -> Int -> Maybe LocalDate
fromParts year month day =
    -- We do all of this processing because our Elm Date library accepts invalid values while most other languages don't.
    --  So we want to maintain consistency.
    -- Oddly, Date has fromCalendarParts, but it's not exposed.
    let
        maybeMonth =
            if month > 0 && month < 13 then
                Just (Date.numberToMonth month)

            else
                Nothing
    in
    maybeMonth
        |> Maybe.map
            (\m ->
                ( m, Date.fromCalendarDate year m day )
            )
        |> Maybe.map
            (\( dateMonth, date ) ->
                if Date.year date == year && Date.month date == dateMonth && Date.day date == day then
                    Just date

                else
                    Nothing
            )
        |> Maybe.withDefault Nothing



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
