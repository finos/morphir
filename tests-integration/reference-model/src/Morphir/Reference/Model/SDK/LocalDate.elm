module Morphir.Reference.Model.SDK.LocalDate exposing (..)

import Morphir.SDK.LocalDate as Date exposing (..)


day : LocalDate -> Int
day date =
    Date.day date


dayOfWeek : LocalDate -> DayOfWeek
dayOfWeek date =
    Date.dayOfWeek date


diffInDays : LocalDate -> LocalDate -> Int
diffInDays fromDate toDate =
    Date.diffInDays fromDate toDate


{-| Find the number of weeks between the given dates.
-}
diffInWeeks : LocalDate -> LocalDate -> Int
diffInWeeks fromDate toDate =
    Date.diffInWeeks fromDate toDate


{-| Find the number of months between the given dates.
-}
diffInMonths : LocalDate -> LocalDate -> Int
diffInMonths fromDate toDate =
    Date.diffInMonths fromDate toDate


{-| Find the number of years between the given dates.
-}
diffInYears : LocalDate -> LocalDate -> Int
diffInYears fromDate toDate =
    Date.diffInYears fromDate toDate


{-| Add the given days to a given date.
-}
addDays : Int -> LocalDate -> LocalDate
addDays count date =
    Date.addDays count date


{-| Add the given weeks to a given date.
-}
addWeeks : Int -> LocalDate -> LocalDate
addWeeks count date =
    Date.addWeeks count date


{-| Add the given months to a given date.
-}
addMonths : Int -> LocalDate -> LocalDate
addMonths count date =
    Date.addMonths count date


{-| Add the given years to a given date.
-}
addYears : Int -> LocalDate -> LocalDate
addYears count date =
    Date.addYears count date


{-| Create a date from a [calendar date][gregorian]: a year, month, and day of
the month. Out-of-range day values will be clamped.

    import Morphir.SDK.LocalDate exposing (fromCalendarDate, Month(..))

    fromCalendarDate 2018 September 26

[gregorian]: https://en.wikipedia.org/wiki/Proleptic_Gregorian_calendar

-}
fromCalendarDate : Int -> Month -> Int -> LocalDate
fromCalendarDate y m d =
    Date.fromCalendarDate y m d


{-| Construct a LocalDate based on ISO formatted string. Opportunity for error denoted by Maybe return type.
-}
fromISO : String -> Maybe LocalDate
fromISO iso =
    Date.fromISO iso


{-| Returns true if the date falls on a weekend (Saturday or Sunday).
-}
isWeekend : LocalDate -> Bool
isWeekend date =
    Date.isWeekend date


{-| Returns true if the date falls on a weekday (any day other than Saturday or Sunday).
-}
isWeekday : LocalDate -> Bool
isWeekday date =
    Date.isWeekday date


{-| Convert a LocalDate to a string in ISO format.
-}
toISOString : LocalDate -> String
toISOString localDate =
    Date.toISOString localDate


{-| Create a date from an [ordinal date][ordinaldate]: a year and day of the
year. Out-of-range day values will be clamped.

    import Morphir.SDK.LocalDate exposing (fromOrdinalDate)

    fromOrdinalDate 2018 269

[ordinaldate]: https://en.wikipedia.org/wiki/Ordinal_date

-}
fromOrdinalDate : Int -> Int -> LocalDate
fromOrdinalDate y dayOfYear =
    Date.fromOrdinalDate y dayOfYear


{-| Construct a LocalDate based on Year, Month, Day. Opportunity for error denoted by Maybe return type.
Errors can occur when any of the given values fall outside of their relevant constraints.
For example, the date given as 2000 2 30 (2000-Feb-30) would fail because the day of the 30th is impossible.
-}
fromParts : Int -> Int -> Int -> Maybe LocalDate
fromParts y m d =
    Date.fromParts y m d


month : LocalDate -> Month
month date =
    Date.month date


monthNumber : LocalDate -> Int
monthNumber date =
    Date.monthNumber date


monthToInt : Month -> Int
monthToInt m =
    Date.monthToInt m


year : LocalDate -> Int
year date =
    Date.year date
