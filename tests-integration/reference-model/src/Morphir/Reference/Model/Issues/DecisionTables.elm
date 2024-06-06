module Morphir.Reference.Model.Issues.DecisionTables exposing (..)

--
--basicPatternMatch : String -> Int
--basicPatternMatch a =
--    case a of
--        "a" ->
--            1
--
--        _ ->
--            2
--
--
--doublePatternMatch : String -> String -> Int
--doublePatternMatch a b =
--    case ( a, b ) of
--        ( "a", "b" ) ->
--            1
--
--        _ ->
--            2
--
--
--triplePatternMatch : String -> string -> String -> Int
--triplePatternMatch a b c =
--    case ( a, b, c ) of
--        ( "a", _, "c" ) ->
--            1
--
--        _ ->
--            2
--
--
--foo : ( String, String )
--foo =
--    ( "a", "b" )
--
--
--bar : Int
--bar =
--    case foo of
--        ( "a", "b" ) ->
--            1
--
--        _ ->
--            2
--
--
--inline : Int
--inline =
--    case "hi" of
--        "hi" ->
--            1
--
--        _ ->
--            2
--
--
--multipleCasePatternMatch : Int -> Int -> String
--multipleCasePatternMatch a b =
--    case ( a, b ) of
--        ( 1, 1 ) ->
--            "1"
--
--        ( 2, 2 ) ->
--            "2"
--
--        _ ->
--            "3"


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



--
--
--type Person
--    = Anonymous
--    | Named String
--    | NamedWithAge String Int
--
--
--myEnum : Person
--myEnum =
--    NamedWithAge "Jane Doe" 18
--
--
--type Employee
--    = Employed Person String
--
--
--enumPatternMatch : Person -> Int
--enumPatternMatch enum =
--    case enum of
--        Anonymous ->
--            1
--
--        Named "John Doe" ->
--            2
--
--        Named name ->
--            3
--
--        NamedWithAge "John Doe" 21 ->
--            4
--
--        NamedWithAge "Jane Doe" _ ->
--            5
--
--        NamedWithAge name age ->
--            6
--
--        _ ->
--            7
--
--
--nestedEnumPatternMatch : Employee -> Int
--nestedEnumPatternMatch enum =
--    case enum of
--        Employed Anonymous "John's Company" ->
--            1
--
--        Employed Anonymous employment ->
--            2
--
--        Employed (Named "John Doe") "John's Company" ->
--            3
--
--        Employed (Named "Jane Doe") company ->
--            5
--
--        Employed (NamedWithAge "John Smith" 21) "FooBar" ->
--            5
--
--        _ ->
--            6
--
--
--variableEnumPatternMatch : Int
--variableEnumPatternMatch =
--    case myEnum of
--        Anonymous ->
--            1
--
--        Named "John Doe" ->
--            2
--
--        Named name ->
--            3
--
--        NamedWithAge "Jane Doe" 18 ->
--            4
--
--        NamedWithAge name employment ->
--            5
--
--        _ ->
--            6
--
--
--type alias Record =
--    { x : Int
--    , y : Int
--    }
--
--
--recordPatternMatch : Record -> String
--recordPatternMatch record =
--    case record.x of
--        1 ->
--            "3"
--
--        _ ->
--            "pass"
