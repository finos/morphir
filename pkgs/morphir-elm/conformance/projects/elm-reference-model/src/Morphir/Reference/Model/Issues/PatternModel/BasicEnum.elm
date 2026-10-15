module Morphir.Reference.Model.Issues.PatternModel.BasicEnum exposing (..)


type BasicEnum
    = One
    | Two
    | Three
    | Four
    | Five
    | Six
    | None


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


stringToEnum : String -> BasicEnum
stringToEnum string =
    case string of
        "1" ->
            One

        "2" ->
            Two

        "3" ->
            Three

        "4" ->
            Four

        "5" ->
            Five

        "6" ->
            Six

        _ ->
            None
