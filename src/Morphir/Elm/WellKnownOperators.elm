module Morphir.Elm.WellKnownOperators exposing (wellKnownOperators)

-- Temporarily included until this is released in elm-syntax

import Dict
import Elm.Dependency exposing (Dependency)
import Elm.Interface exposing (Exposed(..))
import Elm.Syntax.Infix exposing (InfixDirection(..))
import Elm.Syntax.Node exposing (Node(..))
import Elm.Syntax.Range exposing (emptyRange)


wellKnownOperators : List Dependency
wellKnownOperators =
    [ elmCore ]


elmCore : Dependency
elmCore =
    { interfaces =
        Dict.fromList
            [ ( [ "Array" ]
              , [ CustomType ( "Array", [] )
                , Function "empty"
                , Function "isEmpty"
                , Function "length"
                , Function "initialize"
                , Function "repeat"
                , Function "fromList"
                , Function "get"
                , Function "set"
                , Function "push"
                , Function "toList"
                , Function "toIndexedList"
                , Function "foldr"
                , Function "foldl"
                , Function "filter"
                , Function "map"
                , Function "indexedMap"
                , Function "append"
                , Function "slice"
                ]
              )
            , ( [ "Basics" ]
              , [ CustomType ( "Int", [] )
                , CustomType ( "Float", [] )
                , Operator { direction = Node emptyRange Left, function = Node emptyRange "add", operator = Node emptyRange "+", precedence = Node emptyRange 6 }
                , Operator { direction = Node emptyRange Left, function = Node emptyRange "sub", operator = Node emptyRange "-", precedence = Node emptyRange 6 }
                , Operator { direction = Node emptyRange Left, function = Node emptyRange "mul", operator = Node emptyRange "*", precedence = Node emptyRange 7 }
                , Operator { direction = Node emptyRange Left, function = Node emptyRange "fdiv", operator = Node emptyRange "/", precedence = Node emptyRange 7 }
                , Operator { direction = Node emptyRange Left, function = Node emptyRange "idiv", operator = Node emptyRange "//", precedence = Node emptyRange 7 }
                , Operator { direction = Node emptyRange Right, function = Node emptyRange "pow", operator = Node emptyRange "^", precedence = Node emptyRange 8 }
                , Function "toFloat"
                , Function "round"
                , Function "floor"
                , Function "ceiling"
                , Function "truncate"
                , Operator { direction = Node emptyRange Non, function = Node emptyRange "eq", operator = Node emptyRange "==", precedence = Node emptyRange 4 }
                , Operator { direction = Node emptyRange Non, function = Node emptyRange "neq", operator = Node emptyRange "/=", precedence = Node emptyRange 4 }
                , Operator { direction = Node emptyRange Non, function = Node emptyRange "lt", operator = Node emptyRange "<", precedence = Node emptyRange 4 }
                , Operator { direction = Node emptyRange Non, function = Node emptyRange "gt", operator = Node emptyRange ">", precedence = Node emptyRange 4 }
                , Operator { direction = Node emptyRange Non, function = Node emptyRange "le", operator = Node emptyRange "<=", precedence = Node emptyRange 4 }
                , Operator { direction = Node emptyRange Non, function = Node emptyRange "ge", operator = Node emptyRange ">=", precedence = Node emptyRange 4 }
                , Function "max"
                , Function "min"
                , Function "compare"
                , CustomType ( "Order", [ "LT", "EQ", "GT" ] )
                , CustomType ( "Bool", [ "True", "False" ] )
                , Function "not"
                , Operator { direction = Node emptyRange Right, function = Node emptyRange "and", operator = Node emptyRange "&&", precedence = Node emptyRange 3 }
                , Operator { direction = Node emptyRange Right, function = Node emptyRange "or", operator = Node emptyRange "||", precedence = Node emptyRange 2 }
                , Function "xor"
                , Operator { direction = Node emptyRange Right, function = Node emptyRange "append", operator = Node emptyRange "++", precedence = Node emptyRange 5 }
                , Function "modBy"
                , Function "remainderBy"
                , Function "negate"
                , Function "abs"
                , Function "clamp"
                , Function "sqrt"
                , Function "logBase"
                , Function "e"
                , Function "pi"
                , Function "cos"
                , Function "sin"
                , Function "tan"
                , Function "acos"
                , Function "asin"
                , Function "atan"
                , Function "atan2"
                , Function "degrees"
                , Function "radians"
                , Function "turns"
                , Function "toPolar"
                , Function "fromPolar"
                , Function "isNaN"
                , Function "isInfinite"
                , Function "identity"
                , Function "always"
                , Operator { direction = Node emptyRange Right, function = Node emptyRange "apL", operator = Node emptyRange "<|", precedence = Node emptyRange 0 }
                , Operator { direction = Node emptyRange Left, function = Node emptyRange "apR", operator = Node emptyRange "|>", precedence = Node emptyRange 0 }
                , Operator { direction = Node emptyRange Left, function = Node emptyRange "composeL", operator = Node emptyRange "<<", precedence = Node emptyRange 9 }
                , Operator { direction = Node emptyRange Right, function = Node emptyRange "composeR", operator = Node emptyRange ">>", precedence = Node emptyRange 9 }
                , CustomType ( "Never", [] )
                , Function "never"
                ]
              )
            , ( [ "Bitwise" ], [ Function "and", Function "or", Function "xor", Function "complement", Function "shiftLeftBy", Function "shiftRightBy", Function "shiftRightZfBy" ] )
            , ( [ "Char" ], [ CustomType ( "Char", [] ), Function "isUpper", Function "isLower", Function "isAlpha", Function "isAlphaNum", Function "isDigit", Function "isOctDigit", Function "isHexDigit", Function "toUpper", Function "toLower", Function "toLocaleUpper", Function "toLocaleLower", Function "toCode", Function "fromCode" ] )
            , ( [ "Debug" ], [ Function "toString", Function "log", Function "todo" ] )
            , ( [ "Dict" ], [ CustomType ( "Dict", [] ), Function "empty", Function "singleton", Function "insert", Function "update", Function "remove", Function "isEmpty", Function "member", Function "get", Function "size", Function "keys", Function "values", Function "toList", Function "fromList", Function "map", Function "foldl", Function "foldr", Function "filter", Function "partition", Function "union", Function "intersect", Function "diff", Function "merge" ] )
            , ( [ "List" ], [ Function "singleton", Function "repeat", Function "range", Operator { direction = Node emptyRange Right, function = Node emptyRange "cons", operator = Node emptyRange "::", precedence = Node emptyRange 5 }, Function "map", Function "indexedMap", Function "foldl", Function "foldr", Function "filter", Function "filterMap", Function "length", Function "reverse", Function "member", Function "all", Function "any", Function "maximum", Function "minimum", Function "sum", Function "product", Function "append", Function "concat", Function "concatMap", Function "intersperse", Function "map2", Function "map3", Function "map4", Function "map5", Function "sort", Function "sortBy", Function "sortWith", Function "isEmpty", Function "head", Function "tail", Function "take", Function "drop", Function "partition", Function "unzip" ] )
            , ( [ "Maybe" ], [ CustomType ( "Maybe", [ "Just", "Nothing" ] ), Function "andThen", Function "map", Function "map2", Function "map3", Function "map4", Function "map5", Function "withDefault" ] )
            , ( [ "Platform" ], [ CustomType ( "Program", [] ), Function "worker", CustomType ( "Task", [] ), CustomType ( "ProcessId", [] ), CustomType ( "Router", [] ), Function "sendToApp", Function "sendToSelf" ] )
            , ( [ "Platform", "Cmd" ], [ CustomType ( "Cmd", [] ), Function "none", Function "batch", Function "map" ] )
            , ( [ "Platform", "Sub" ], [ CustomType ( "Sub", [] ), Function "none", Function "batch", Function "map" ] )
            , ( [ "Process" ], [ Alias "Id", Function "spawn", Function "sleep", Function "kill" ] )
            , ( [ "Result" ], [ CustomType ( "Result", [ "Ok", "Err" ] ), Function "withDefault", Function "map", Function "map2", Function "map3", Function "map4", Function "map5", Function "andThen", Function "toMaybe", Function "fromMaybe", Function "mapError" ] )
            , ( [ "Set" ], [ CustomType ( "Set", [] ), Function "empty", Function "singleton", Function "insert", Function "remove", Function "isEmpty", Function "member", Function "size", Function "union", Function "intersect", Function "diff", Function "toList", Function "fromList", Function "map", Function "foldl", Function "foldr", Function "filter", Function "partition" ] )
            , ( [ "String" ], [ CustomType ( "String", [] ), Function "isEmpty", Function "length", Function "reverse", Function "repeat", Function "replace", Function "append", Function "concat", Function "split", Function "join", Function "words", Function "lines", Function "slice", Function "left", Function "right", Function "dropLeft", Function "dropRight", Function "contains", Function "startsWith", Function "endsWith", Function "indexes", Function "indices", Function "toInt", Function "fromInt", Function "toFloat", Function "fromFloat", Function "fromChar", Function "cons", Function "uncons", Function "toList", Function "fromList", Function "toUpper", Function "toLower", Function "pad", Function "padLeft", Function "padRight", Function "trim", Function "trimLeft", Function "trimRight", Function "map", Function "filter", Function "foldl", Function "foldr", Function "any", Function "all" ] )
            , ( [ "Task" ], [ Alias "Task", Function "succeed", Function "fail", Function "map", Function "map2", Function "map3", Function "map4", Function "map5", Function "sequence", Function "andThen", Function "onError", Function "mapError", Function "perform", Function "attempt" ] )
            , ( [ "Tuple" ], [ Function "pair", Function "first", Function "second", Function "mapFirst", Function "mapSecond", Function "mapBoth" ] )
            ]
    , name = "elm/core"
    , version = "1.0.5"
    }
