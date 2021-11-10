module Morphir.Reference.Model.Example exposing (..)

import Morphir.Reference.Model.Issues.PatternModel.BasicEnum exposing (BasicEnum(..))
enumToString : BasicEnum -> String
enumToString enum =
    case enum of
        One ->
            "1"

        Two ->
            "2"

        Three ->
            "3"

        Four ->
            "4"

        Five ->
            "5"

        Six ->
            "6"

        None ->
            ""