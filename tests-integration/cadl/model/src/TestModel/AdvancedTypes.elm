module TestModel.AdvancedTypes exposing (..)

import Morphir.SDK.Decimal exposing (Decimal)
import Morphir.SDK.LocalDate exposing (LocalDate)
import Morphir.SDK.LocalTime exposing (LocalTime)
import Morphir.SDK.Month exposing (Month)


type alias Price =
    Decimal


type alias DateOfBirth =
    LocalDate


type alias CurrentTime =
    LocalTime


type alias CurrentMonth =
    Month
