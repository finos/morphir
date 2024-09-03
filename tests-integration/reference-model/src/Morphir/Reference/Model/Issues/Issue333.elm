module Morphir.Reference.Model.Issues.Issue333 exposing (..)


type Month
    = January
    | February
    | March
    | April
    | May
    | June
    | July
    | August
    | September
    | October
    | November
    | December


type MonthParseError
    = InvalidMonth Int


type alias RawLocalDate =
    { year : Int
    , month : Int
    , day : Int
    }


type alias ValidLocalDate =
    { year : Int
    , month : Month
    , day : Int
    }


type LocalDate
    = Invalid RawLocalDate
    | Valid ValidLocalDate


monthNumber : Month -> Int
monthNumber month =
    case month of
        January ->
            1

        February ->
            2

        March ->
            3

        April ->
            4

        May ->
            5

        June ->
            6

        July ->
            7

        August ->
            8

        September ->
            9

        October ->
            10

        November ->
            11

        December ->
            12


fromInt : Int -> Maybe Month
fromInt month =
    case month of
        1 ->
            Just January

        2 ->
            Just February

        3 ->
            Just March

        4 ->
            Just April

        5 ->
            Just May

        6 ->
            Just June

        7 ->
            Just July

        8 ->
            Just August

        9 ->
            Just September

        10 ->
            Just October

        11 ->
            Just November

        12 ->
            Just December

        _ ->
            Nothing


convertFromInt : Int -> Result MonthParseError Month
convertFromInt month =
    case month of
        1 ->
            Ok January

        2 ->
            Ok February

        3 ->
            Ok March

        4 ->
            Ok April

        5 ->
            Ok May

        6 ->
            Ok June

        7 ->
            Ok July

        8 ->
            Ok August

        9 ->
            Ok September

        10 ->
            Ok October

        11 ->
            Ok November

        12 ->
            Ok December

        m ->
            InvalidMonth m |> Err


fold : (RawLocalDate -> out) -> (ValidLocalDate -> out) -> LocalDate -> out
fold whenInvalid whenValid date =
    case date of
        Valid validDate ->
            whenValid validDate

        Invalid rawDate ->
            whenInvalid rawDate
