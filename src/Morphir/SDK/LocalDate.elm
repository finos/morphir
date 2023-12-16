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
    , fromCalendarDate, fromISO, fromOrdinalDate, fromParts
    , toISOString, monthToInt
    , DayOfWeek(..), dayOfWeek, isWeekend, isWeekday
    , Month(..)
    , year, month, monthNumber, day
    )

{-| This module adds the definition of a date without time zones. Useful in business modeling.


# Types

@docs LocalDate


# Date Math

@docs diffInDays, diffInWeeks, diffInMonths, diffInYears
@docs addDays, addWeeks, addMonths, addYears


# Constructors

@docs fromCalendarDate, fromISO, fromOrdinalDate, fromParts


# Convert

@docs toISOString, monthToInt


# Query

@docs DayOfWeek, dayOfWeek, isWeekend, isWeekday
@docs Month
@docs year, month, monthNumber, day

-}

import Date exposing (Date, Unit(..))
import Time


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


{-| Create a date from a [calendar date][gregorian]: a year, month, and day of
the month. Out-of-range day values will be clamped.

    import Morphir.SDK.LocalDate exposing (fromCalendarDate, Month(..))

    fromCalendarDate 2018 September 26

[gregorian]: https://en.wikipedia.org/wiki/Proleptic_Gregorian_calendar

-}
fromCalendarDate : Int -> Month -> Int -> LocalDate
fromCalendarDate y m d =
    Date.fromCalendarDate y (monthToMonth m) d


{-| Create a date from an [ordinal date][ordinaldate]: a year and day of the
year. Out-of-range day values will be clamped.

    import Morphir.SDK.LocalDate exposing (fromOrdinalDate)

    fromOrdinalDate 2018 269

[ordinaldate]: https://en.wikipedia.org/wiki/Ordinal_date

-}
fromOrdinalDate : Int -> Int -> LocalDate
fromOrdinalDate y dayOfYear =
    Date.fromOrdinalDate y dayOfYear


{-| Construct a LocalDate based on ISO formatted string. Opportunity for error denoted by Maybe return type.
-}
fromISO : String -> Maybe LocalDate
fromISO iso =
    Date.fromIsoString iso |> Result.toMaybe


{-| Convert a LocalDate to a string in ISO format.
-}
toISOString : LocalDate -> String
toISOString localDate =
    Date.toIsoString localDate


{-| Construct a LocalDate based on Year, Month, Day. Opportunity for error denoted by Maybe return type.
Errors can occur when any of the given values fall outside of their relevant constraints.
For example, the date given as 2000 2 30 (2000-Feb-30) would fail because the day of the 30th is impossible.
-}
fromParts : Int -> Int -> Int -> Maybe LocalDate
fromParts yearNumber monthNum dayOfMonthNumber =
    -- We do all of this processing because our Elm Date library accepts invalid values while most other languages don't.
    --  So we want to maintain consistency.
    -- Oddly, Date has fromCalendarParts, but it's not exposed.
    let
        maybeMonth =
            if monthNum > 0 && monthNum < 13 then
                Just (Date.numberToMonth monthNum)

            else
                Nothing
    in
    maybeMonth
        |> Maybe.map
            (\m ->
                ( m, Date.fromCalendarDate yearNumber m dayOfMonthNumber )
            )
        |> Maybe.map
            (\( dateMonth, date ) ->
                if Date.year date == yearNumber && Date.month date == dateMonth && Date.day date == dayOfMonthNumber then
                    Just date

                else
                    Nothing
            )
        |> Maybe.withDefault Nothing


{-| Returns the year as a number.
-}
year : LocalDate -> Int
year localDate =
    Date.year localDate


{-| Returns the month of the year for a given date.
-}
month : LocalDate -> Month
month localDate =
    case Date.month localDate of
        Time.Jan ->
            January

        Time.Feb ->
            February

        Time.Mar ->
            March

        Time.Apr ->
            April

        Time.May ->
            May

        Time.Jun ->
            June

        Time.Jul ->
            July

        Time.Aug ->
            August

        Time.Sep ->
            September

        Time.Oct ->
            October

        Time.Nov ->
            November

        Time.Dec ->
            December


{-| Returns the month of the year as an Int, where January is month 1 and December is month 12.
-}
monthNumber : LocalDate -> Int
monthNumber localDate =
    case Date.month localDate of
        Time.Jan ->
            1

        Time.Feb ->
            2

        Time.Mar ->
            3

        Time.Apr ->
            4

        Time.May ->
            5

        Time.Jun ->
            6

        Time.Jul ->
            7

        Time.Aug ->
            8

        Time.Sep ->
            9

        Time.Oct ->
            10

        Time.Nov ->
            11

        Time.Dec ->
            12


{-| Converts a Month to an Int, where January is month 1 and December is month 12.
-}
monthToInt : Month -> Int
monthToInt m =
    case m of
        January ->
            1

        February ->
            2

        March ->
            3

        April ->
            4

        May ->
            5

        June ->
            6

        July ->
            7

        August ->
            8

        September ->
            9

        October ->
            10

        November ->
            11

        December ->
            12


monthToMonth : Month -> Time.Month
monthToMonth m =
    case m of
        January ->
            Time.Jan

        February ->
            Time.Feb

        March ->
            Time.Mar

        April ->
            Time.Apr

        May ->
            Time.May

        June ->
            Time.Jun

        July ->
            Time.Jul

        August ->
            Time.Aug

        September ->
            Time.Sep

        October ->
            Time.Oct

        November ->
            Time.Nov

        December ->
            Time.Dec


{-| The day of the month (1–31).
-}
day : LocalDate -> Int
day localDate =
    Date.day localDate


{-| Returns the day of week for a date.
-}
dayOfWeek : LocalDate -> DayOfWeek
dayOfWeek localDate =
    case Date.weekday localDate of
        Time.Mon ->
            Monday

        Time.Tue ->
            Tuesday

        Time.Wed ->
            Wednesday

        Time.Thu ->
            Thursday

        Time.Fri ->
            Friday

        Time.Sat ->
            Saturday

        Time.Sun ->
            Sunday


{-| Returns true if the date falls on a weekend (Saturday or Sunday).
-}
isWeekend : LocalDate -> Bool
isWeekend localDate =
    case dayOfWeek localDate of
        Saturday ->
            True

        Sunday ->
            True

        _ ->
            False


{-| Returns true if the date falls on a weekday (any day other than Saturday or Sunday).
-}
isWeekday : LocalDate -> Bool
isWeekday localDate =
    not (isWeekend localDate)


{-| Type that represents a day of the week.
-}
type DayOfWeek
    = Monday
    | Tuesday
    | Wednesday
    | Thursday
    | Friday
    | Saturday
    | Sunday


{-| Gregorian calendar months in English.
-}
type Month
    = January
    | February
    | March
    | April
    | May
    | June
    | July
    | August
    | September
    | October
    | November
    | December
