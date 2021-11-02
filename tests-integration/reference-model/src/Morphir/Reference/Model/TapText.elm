module Morphir.Reference.Model.TapText exposing (..)


basicPatternMatch : String -> Int
basicPatternMatch a =
    case a of
        "a" ->
            1

        _ ->
            2


doublePatternMatch : String -> String -> Int
doublePatternMatch a b =
    case ( a, b ) of
        ( "a", "b" ) ->
            1

        _ ->
            2



request : Int -> Int -> Result String Int
request a b =
    if a <= b then
        Ok a

    else
        Err "a is greater than b"


