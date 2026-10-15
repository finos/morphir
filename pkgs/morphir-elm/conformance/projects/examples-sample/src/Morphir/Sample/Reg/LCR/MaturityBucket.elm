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


module Morphir.Sample.Reg.LCR.MaturityBucket exposing (..)

-- See: https://www.federalreserve.gov/reportforms/forms/FR_2052a20190331_f.pdf
-- Appendix IV-a, Maturity Time Bucket Value List on page 75

import Morphir.SDK.LocalDate exposing (LocalDate, diffInDays, diffInYears)


type MaturityBucket
    = Daily Int
    | DayRange Int Int
    | DayYear Int Int
    | Yearly Int Int
    | Residual


daysToMaturity : LocalDate -> LocalDate -> Int
daysToMaturity fromDate maturityDate =
    diffInDays maturityDate fromDate


yearsToMaturity : LocalDate -> LocalDate -> Int
yearsToMaturity fromDate maturityDate =
    diffInYears maturityDate fromDate


{-| The Fed spec on maturity buckets
-}
bucket : LocalDate -> LocalDate -> MaturityBucket
bucket fromDate maturityDate =
    let
        days : Int
        days =
            daysToMaturity fromDate maturityDate

        years : Int
        years =
            yearsToMaturity maturityDate fromDate
    in
    if days <= 60 then
        Daily days

    else if days <= 67 then
        DayRange 61 67

    else if days <= 74 then
        DayRange 68 74

    else if days <= 82 then
        DayRange 75 82

    else if days <= 90 then
        DayRange 83 90

    else if days <= 120 then
        DayRange 92 120

    else if days <= 150 then
        DayRange 121 150

    else if days <= 180 then
        DayRange 151 180

    else if days <= 270 then
        DayYear 181 270

    else if years <= 1 then
        DayYear 271 1

    else if years <= 2 then
        Yearly 1 2

    else if years <= 3 then
        Yearly 2 3

    else if years <= 4 then
        Yearly 3 4

    else if years <= 5 then
        Yearly 4 5

    else
        Residual
