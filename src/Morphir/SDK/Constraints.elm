module Morphir.SDK.Constraints exposing (..)

import Regex exposing (Regex)


type alias IntConstraint =
    { minValue : Int
    , range : Int
    }


type StringConstraint
    = StringSizeConstraint StringSizeConstraint
    | StringRegexConstraint Regex


type alias StringSizeConstraint =
    { minLength : Maybe Int
    , maxLength : Int
    }


type DecimalConstraint
    = DecimalSizeConstraint DecimalSizeConstraint


type alias DecimalSizeConstraint =
    { size : Int
    , precision : Int
    }
