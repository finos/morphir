module Morphir.Elm.Common exposing (..)

import Dict exposing (Dict)


inlineOperators : Dict String String
inlineOperators =
    Dict.fromList
        [ ( "Basics.and", "&&" )
        , ( "Basics.or", "||" )
        , ( "Basics.and", "&&" )
        , ( "Basics.add", "+" )
        , ( "Basics.subtract", "-" )
        , ( "Basics.multiply", "*" )
        , ( "Basics.divide", "/" )
        , ( "Basics.integerDivide", "//" )
        , ( "Basics.equal", "==" )
        , ( "Basics.notEqual", "/=" )
        , ( "Basics.lessThan", "<" )
        , ( "Basics.lessThanOrEqual", "<=" )
        , ( "Basics.greaterThan", ">" )
        , ( "Basics.greaterThanOrEqual", ">=" )
        , ( "Basics.append", "++" )
        , ( "Basics.power", "^" )
        , ( "Basics.composeLeft", "<|" )
        , ( "Basics.composeRight", "|>" )
        , ( "List.cons", "::" )
        ]


mapOperators : String -> String
mapOperators operatorName =
    inlineOperators
        |> Dict.get operatorName
        |> Maybe.withDefault operatorName
        |> appendBraces


appendBraces : String -> String
appendBraces string =
    "(" ++ string ++ ")"
