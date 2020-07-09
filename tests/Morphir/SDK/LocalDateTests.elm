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
