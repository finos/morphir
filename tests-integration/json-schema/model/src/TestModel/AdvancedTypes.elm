module TestModel.AdvancedTypes exposing (..)

import Morphir.SDK.Decimal exposing (..)
import Morphir.SDK.LocalDate exposing (LocalDate, Month)
import Morphir.SDK.LocalTime exposing (LocalTime)

import TestModel.BasicTypes exposing (..)


type alias Score =
    Decimal


type alias AcquisitionDate =
    LocalDate


type alias EntryTime =
    LocalTime


type alias StartMonth =
    Month

type alias Exam =
    Grade
