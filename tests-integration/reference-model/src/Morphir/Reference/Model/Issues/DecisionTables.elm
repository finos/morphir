module Morphir.Reference.Model.Issues.DecisionTables exposing (..)


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


triplePatternMatch : String -> string -> String -> Int
triplePatternMatch a b c =
    case ( a, b, c ) of
        ( "a", _, "c" ) ->
            1

        _ ->
            2


foo : ( String, String )
foo =
    ( "a", "b" )


bar : Int
bar =
    case foo of
        ( "a", "b" ) ->
            1

        _ ->
            2


inline : Int
inline =
    case "hi" of
        "hi" ->
            1

        _ ->
            2


multipleCasePatternMatch : Int -> Int -> String
multipleCasePatternMatch a b =
    case ( a, b ) of
        ( 1, 1 ) ->
            "1"

        ( 2, 2 ) ->
            "2"

        _ ->
            "3"


nestedPatternMatch : String -> String -> String -> String -> String -> Int
nestedPatternMatch a b c d e =
    case a of
        "a" ->
            case b of
                "b" ->
                    case ( c, d ) of
                        ( "c", "d" ) ->
                            1

                        _ ->
                            2

                _ ->
                    3

        _ ->
            case e of
                "e" ->
                    4

                _ ->
                    5
