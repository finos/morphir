module Morphir.SDK.Date exposing (..)

{-| A `Date` is a representation of a day of the calendar without consideration for location.
    This module defines local date operations.

    @docs Date
-}

import Morphir.SDK.Int exposing (Int)


type alias Date =
    Basics.Date


type alias RataDie =
    Int


{-| Represents a date using the Rata Die system.

This has the advantage of making Date comparable since Int is comparable. 
-}
type alias Date =
    Native RataDie


year : Date -> Int
year ld =
    native 
        (ld
            |> Date.fromRataDie 
            |> Date.year
        )


plusYears : Int -> Date -> Date
plusYears yearCount ld =
    native
        (ld 
            |> Date.fromRataDie 
            |> Date.add Date.Years yearCount 
            |> Date.toRataDie
        )    


month : Date -> Int
month ld = 
    native 
        (ld 
            |> Date.fromRataDie 
            |> Date.monthNumber
        )    


plusMonths : Int -> Date -> Date
plusMonths monthCount ld =
    native
        (ld 
            |> Date.fromRataDie 
            |> Date.add Date.Months monthCount 
            |> Date.toRataDie
        )


day : Date -> Int
day ld = 
    native
        (ld 
            |> Date.fromRataDie 
            |> Date.day
        )  


plusDays : Int -> Date -> Date
plusDays dayCount ld =
    native
        (ld 
            |> Date.fromRataDie 
            |> Date.add Date.Days dayCount 
            |> Date.toRataDie
        )


diffInDays : Date -> Date -> Int
diffInDays ld1 ld2 = 
    native
        (Date.diff
            Date.Days
            (ld1 |> Date.fromRataDie)
            (ld2 |> Date.fromRataDie)
        )


type alias Month = 
    Native Date.Month


lastDayOfMonth : Month -> Int -> Date
lastDayOfMonth m y = 
    native
        (Date.fromCalendarDate y m 1
            |> Date.add Date.Months 1
            |> Date.add Date.Days -1 
            |> Date.toRataDie
        )
