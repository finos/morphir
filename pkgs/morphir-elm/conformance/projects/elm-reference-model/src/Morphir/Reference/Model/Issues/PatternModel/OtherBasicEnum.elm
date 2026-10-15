module Morphir.Reference.Model.Issues.PatternModel.OtherBasicEnum exposing (..)


type OtherBasicEnum
    = A
    | B
    | C
    | D
    | E
    | F
    | None


enumToString : OtherBasicEnum -> String
enumToString enum =
    case enum of
        A ->
            "Alpha"

        B ->
            "Bravo"

        C ->
            "Charlie"

        D ->
            "Delta"

        E ->
            "Echo"

        F ->
            "Foxtrot"

        None ->
            "None"


stringToEnum : String -> OtherBasicEnum
stringToEnum string =
    case string of
        "Alpha" ->
            A

        "Bravo" ->
            B

        "Charlie" ->
            C

        "Delta" ->
            D

        "Echo" ->
            E

        "Foxtrot" ->
            F

        _ ->
            None
