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


type Enum
    = First
    | Second String
    | Third String Int


myEnum : Enum
myEnum =
    Second "foo"


type OtherEnum
    = One Enum String


enumPatternMatch : Enum -> Int
enumPatternMatch enum =
    case enum of
        First ->
            1

        Second str ->
            2

        Second "specific value" ->
            3

        Third str int ->
            4

        _ ->
            5


nestedEnumPatternMatch : OtherEnum -> Int
nestedEnumPatternMatch enum =
    case enum of
        One First str ->
            1

        One (Second str) str2 ->
            2

        One (Second "specific") "value" ->
            3

        One (Third str int) str2 ->
            4

        _ ->
            5


variableEnumPatternMatch : Int
variableEnumPatternMatch =
    case myEnum of
        First ->
            1

        Second str ->
            2

        Second "specific value" ->
            3

        Third str int ->
            4

        _ ->
            5


type alias Record =
    { x : Int
    , y : Int
    }


recordPatternMatch : Record -> String
recordPatternMatch record =
    case record.x of
        1 ->
            "3"

        _ ->
            "pass"
