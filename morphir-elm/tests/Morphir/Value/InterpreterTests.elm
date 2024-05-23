module Morphir.Value.InterpreterTests exposing (..)

import Dict
import Expect
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.FQName exposing (FQName, fqn)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.Package as Package
import Morphir.IR.QName as QName exposing (QName(..))
import Morphir.IR.SDK as SDK
import Morphir.IR.Value as Value
import Morphir.Value.Interpreter exposing (evaluate)
import Test exposing (Test, describe, test)


basicsPendingSDK =
    Ok
        []


listPendingSDK =
    Ok
        [ QName [ [ "list" ] ] [ "sort" ]
        , QName [ [ "list" ] ] [ "sort", "by" ]
        , QName [ [ "list" ] ] [ "sort", "with" ]
        ]


tuplePendingSDK =
    Ok []


stringPendingSDK =
    Ok
        []


compareList : List QName -> List QName -> ModuleName -> Result String (List QName)
compareList sdkList sdkImplementedList moduleName =
    sdkList
        |> List.filter
            (\elem ->
                if sdkImplementedList |> List.member elem then
                    False

                else if QName.getModulePath elem == moduleName then
                    True

                else
                    False
            )
        |> Ok


totalSDK =
    Ok
        [ QName [ [ "aggregate" ] ] [ "aggregate", "map" ]
        , QName [ [ "aggregate" ] ] [ "aggregate", "map", "2" ]
        , QName [ [ "aggregate" ] ] [ "aggregate", "map", "3" ]
        , QName [ [ "aggregate" ] ] [ "average", "of" ]
        , QName [ [ "aggregate" ] ] [ "by", "key" ]
        , QName [ [ "aggregate" ] ] [ "count" ]
        , QName [ [ "aggregate" ] ] [ "maximum", "of" ]
        , QName [ [ "aggregate" ] ] [ "minimum", "of" ]
        , QName [ [ "aggregate" ] ] [ "sum", "of" ]
        , QName [ [ "aggregate" ] ] [ "weighted", "average", "of" ]
        , QName [ [ "aggregate" ] ] [ "with", "filter" ]
        , QName [ [ "basics" ] ] [ "always" ]
        , QName [ [ "basics" ] ] [ "append" ]
        , QName [ [ "basics" ] ] [ "clamp" ]
        , QName [ [ "basics" ] ] [ "compare" ]
        , QName [ [ "basics" ] ] [ "compose", "left" ]
        , QName [ [ "basics" ] ] [ "compose", "right" ]
        , QName [ [ "basics" ] ] [ "identity" ]
        , QName [ [ "basics" ] ] [ "max" ]
        , QName [ [ "basics" ] ] [ "min" ]
        , QName [ [ "basics" ] ] [ "never" ]
        , QName [ [ "basics" ] ] [ "power" ]
        , QName [ [ "decimal" ] ] [ "abs" ]
        , QName [ [ "decimal" ] ] [ "add" ]
        , QName [ [ "decimal" ] ] [ "bps" ]
        , QName [ [ "decimal" ] ] [ "compare" ]
        , QName [ [ "decimal" ] ] [ "div" ]
        , QName [ [ "decimal" ] ] [ "div", "with", "default" ]
        , QName [ [ "decimal" ] ] [ "eq" ]
        , QName [ [ "decimal" ] ] [ "from", "float" ]
        , QName [ [ "decimal" ] ] [ "from", "int" ]
        , QName [ [ "decimal" ] ] [ "from", "string" ]
        , QName [ [ "decimal" ] ] [ "gt" ]
        , QName [ [ "decimal" ] ] [ "gte" ]
        , QName [ [ "decimal" ] ] [ "hundred" ]
        , QName [ [ "decimal" ] ] [ "hundredth" ]
        , QName [ [ "decimal" ] ] [ "lt" ]
        , QName [ [ "decimal" ] ] [ "lte" ]
        , QName [ [ "decimal" ] ] [ "million" ]
        , QName [ [ "decimal" ] ] [ "millionth" ]
        , QName [ [ "decimal" ] ] [ "minus", "one" ]
        , QName [ [ "decimal" ] ] [ "mul" ]
        , QName [ [ "decimal" ] ] [ "negate" ]
        , QName [ [ "decimal" ] ] [ "neq" ]
        , QName [ [ "decimal" ] ] [ "one" ]
        , QName [ [ "decimal" ] ] [ "round" ]
        , QName [ [ "decimal" ] ] [ "shift", "decimal", "left" ]
        , QName [ [ "decimal" ] ] [ "shift", "decimal", "right" ]
        , QName [ [ "decimal" ] ] [ "sub" ]
        , QName [ [ "decimal" ] ] [ "tenth" ]
        , QName [ [ "decimal" ] ] [ "thousand" ]
        , QName [ [ "decimal" ] ] [ "to", "float" ]
        , QName [ [ "decimal" ] ] [ "to", "string" ]
        , QName [ [ "decimal" ] ] [ "truncate" ]
        , QName [ [ "decimal" ] ] [ "zero" ]
        , QName [ [ "dict" ] ] [ "diff" ]
        , QName [ [ "dict" ] ] [ "empty" ]
        , QName [ [ "dict" ] ] [ "filter" ]
        , QName [ [ "dict" ] ] [ "foldl" ]
        , QName [ [ "dict" ] ] [ "foldr" ]
        , QName [ [ "dict" ] ] [ "from", "list" ]
        , QName [ [ "dict" ] ] [ "get" ]
        , QName [ [ "dict" ] ] [ "insert" ]
        , QName [ [ "dict" ] ] [ "intersect" ]
        , QName [ [ "dict" ] ] [ "is", "empty" ]
        , QName [ [ "dict" ] ] [ "keys" ]
        , QName [ [ "dict" ] ] [ "map" ]
        , QName [ [ "dict" ] ] [ "member" ]
        , QName [ [ "dict" ] ] [ "merge" ]
        , QName [ [ "dict" ] ] [ "partition" ]
        , QName [ [ "dict" ] ] [ "remove" ]
        , QName [ [ "dict" ] ] [ "singleton" ]
        , QName [ [ "dict" ] ] [ "size" ]
        , QName [ [ "dict" ] ] [ "to", "list" ]
        , QName [ [ "dict" ] ] [ "union" ]
        , QName [ [ "dict" ] ] [ "update" ]
        , QName [ [ "dict" ] ] [ "values" ]
        , QName [ [ "int" ] ] [ "from", "int", "16" ]
        , QName [ [ "int" ] ] [ "from", "int", "32" ]
        , QName [ [ "int" ] ] [ "from", "int", "64" ]
        , QName [ [ "int" ] ] [ "from", "int", "8" ]
        , QName [ [ "int" ] ] [ "to", "int", "16" ]
        , QName [ [ "int" ] ] [ "to", "int", "32" ]
        , QName [ [ "int" ] ] [ "to", "int", "64" ]
        , QName [ [ "int" ] ] [ "to", "int", "8" ]
        , QName [ [ "key" ] ] [ "key", "0" ]
        , QName [ [ "key" ] ] [ "key", "10" ]
        , QName [ [ "key" ] ] [ "key", "11" ]
        , QName [ [ "key" ] ] [ "key", "12" ]
        , QName [ [ "key" ] ] [ "key", "13" ]
        , QName [ [ "key" ] ] [ "key", "14" ]
        , QName [ [ "key" ] ] [ "key", "15" ]
        , QName [ [ "key" ] ] [ "key", "16" ]
        , QName [ [ "key" ] ] [ "key", "2" ]
        , QName [ [ "key" ] ] [ "key", "3" ]
        , QName [ [ "key" ] ] [ "key", "4" ]
        , QName [ [ "key" ] ] [ "key", "5" ]
        , QName [ [ "key" ] ] [ "key", "6" ]
        , QName [ [ "key" ] ] [ "key", "7" ]
        , QName [ [ "key" ] ] [ "key", "8" ]
        , QName [ [ "key" ] ] [ "key", "9" ]
        , QName [ [ "key" ] ] [ "no", "key" ]
        , QName [ [ "list" ] ] [ "indexed", "map" ]
        , QName [ [ "list" ] ] [ "sort" ]
        , QName [ [ "list" ] ] [ "sort", "by" ]
        , QName [ [ "list" ] ] [ "sort", "with" ]
        , QName [ [ "local", "date" ] ] [ "add", "days" ]
        , QName [ [ "local", "date" ] ] [ "add", "months" ]
        , QName [ [ "local", "date" ] ] [ "add", "weeks" ]
        , QName [ [ "local", "date" ] ] [ "add", "years" ]
        , QName [ [ "local", "date" ] ] [ "diff", "in", "days" ]
        , QName [ [ "local", "date" ] ] [ "diff", "in", "months" ]
        , QName [ [ "local", "date" ] ] [ "diff", "in", "weeks" ]
        , QName [ [ "local", "date" ] ] [ "diff", "in", "years" ]
        , QName [ [ "local", "date" ] ] [ "from", "i", "s", "o" ]
        , QName [ [ "local", "date" ] ] [ "from", "parts" ]
        , QName [ [ "maybe" ] ] [ "and", "then" ]
        , QName [ [ "maybe" ] ] [ "map" ]
        , QName [ [ "maybe" ] ] [ "map", "2" ]
        , QName [ [ "maybe" ] ] [ "map", "3" ]
        , QName [ [ "maybe" ] ] [ "map", "4" ]
        , QName [ [ "maybe" ] ] [ "map", "5" ]
        , QName [ [ "maybe" ] ] [ "with", "default" ]
        , QName [ [ "number" ] ] [ "abs" ]
        , QName [ [ "number" ] ] [ "add" ]
        , QName [ [ "number" ] ] [ "coerce", "to", "decimal" ]
        , QName [ [ "number" ] ] [ "divide" ]
        , QName [ [ "number" ] ] [ "equal" ]
        , QName [ [ "number" ] ] [ "from", "int" ]
        , QName [ [ "number" ] ] [ "greater", "than" ]
        , QName [ [ "number" ] ] [ "greater", "than", "or", "equal" ]
        , QName [ [ "number" ] ] [ "is", "simplified" ]
        , QName [ [ "number" ] ] [ "less", "than" ]
        , QName [ [ "number" ] ] [ "less", "than", "or", "equal" ]
        , QName [ [ "number" ] ] [ "multiply" ]
        , QName [ [ "number" ] ] [ "negate" ]
        , QName [ [ "number" ] ] [ "not", "equal" ]
        , QName [ [ "number" ] ] [ "one" ]
        , QName [ [ "number" ] ] [ "reciprocal" ]
        , QName [ [ "number" ] ] [ "simplify" ]
        , QName [ [ "number" ] ] [ "subtract" ]
        , QName [ [ "number" ] ] [ "to", "decimal" ]
        , QName [ [ "number" ] ] [ "to", "fractional", "string" ]
        , QName [ [ "number" ] ] [ "zero" ]
        , QName [ [ "regex" ] ] [ "contains" ]
        , QName [ [ "regex" ] ] [ "find" ]
        , QName [ [ "regex" ] ] [ "find", "at", "most" ]
        , QName [ [ "regex" ] ] [ "from", "string" ]
        , QName [ [ "regex" ] ] [ "from", "string", "with" ]
        , QName [ [ "regex" ] ] [ "never" ]
        , QName [ [ "regex" ] ] [ "replace" ]
        , QName [ [ "regex" ] ] [ "replace", "at", "most" ]
        , QName [ [ "regex" ] ] [ "split" ]
        , QName [ [ "regex" ] ] [ "split", "at", "most" ]
        , QName [ [ "result" ] ] [ "and", "then" ]
        , QName [ [ "result" ] ] [ "from", "maybe" ]
        , QName [ [ "result" ] ] [ "map" ]
        , QName [ [ "result" ] ] [ "map", "2" ]
        , QName [ [ "result" ] ] [ "map", "3" ]
        , QName [ [ "result" ] ] [ "map", "4" ]
        , QName [ [ "result" ] ] [ "map", "5" ]
        , QName [ [ "result" ] ] [ "map", "error" ]
        , QName [ [ "result" ] ] [ "to", "maybe" ]
        , QName [ [ "result" ] ] [ "with", "default" ]
        , QName [ [ "rule" ] ] [ "any" ]
        , QName [ [ "rule" ] ] [ "any", "of" ]
        , QName [ [ "rule" ] ] [ "chain" ]
        , QName [ [ "rule" ] ] [ "is" ]
        , QName [ [ "rule" ] ] [ "none", "of" ]
        , QName [ [ "set" ] ] [ "diff" ]
        , QName [ [ "set" ] ] [ "empty" ]
        , QName [ [ "set" ] ] [ "filter" ]
        , QName [ [ "set" ] ] [ "foldl" ]
        , QName [ [ "set" ] ] [ "foldr" ]
        , QName [ [ "set" ] ] [ "from", "list" ]
        , QName [ [ "set" ] ] [ "insert" ]
        , QName [ [ "set" ] ] [ "intersect" ]
        , QName [ [ "set" ] ] [ "is", "empty" ]
        , QName [ [ "set" ] ] [ "map" ]
        , QName [ [ "set" ] ] [ "member" ]
        , QName [ [ "set" ] ] [ "partition" ]
        , QName [ [ "set" ] ] [ "remove" ]
        , QName [ [ "set" ] ] [ "singleton" ]
        , QName [ [ "set" ] ] [ "size" ]
        , QName [ [ "set" ] ] [ "to", "list" ]
        , QName [ [ "set" ] ] [ "union" ]
        , QName [ [ "string" ] ] [ "all" ]
        , QName [ [ "string" ] ] [ "any" ]
        , QName [ [ "string" ] ] [ "filter" ]
        , QName [ [ "string" ] ] [ "foldl" ]
        , QName [ [ "string" ] ] [ "foldr" ]
        , QName [ [ "string" ] ] [ "map" ]
        ]


evaluateValueTests : Test
evaluateValueTests =
    let
        positiveCheck : String -> Value.RawValue -> Value.RawValue -> Test
        positiveCheck desc input expectedOutput =
            test desc
                (\_ ->
                    evaluate SDK.nativeFunctions (Library [ [ "empty" ] ] Dict.empty Package.emptyDefinition) input
                        |> Expect.equal
                            (Ok expectedOutput)
                )

        listCheck : String -> List QName -> List QName -> Result String (List QName) -> ModuleName -> Test
        listCheck desc sdkList sdkImplementedList pendingSDK moduleName =
            test desc
                (\_ ->
                    compareList sdkList sdkImplementedList moduleName |> Expect.equal pendingSDK
                )
    in
    describe "evaluateValue"
        [ listCheck "Basic SDK List = Basic SDK Implemented List"
            (SDK.packageSpec.modules
                |> Dict.toList
                |> List.map (\( moduleName, moduleSpec ) -> moduleSpec.values |> Dict.toList |> List.map (\a -> QName.fromTuple ( moduleName, Tuple.first a )))
                |> List.concat
            )
            (SDK.nativeFunctions
                |> Dict.toList
                |> List.map (\( ( _, moduleName, localName ), _ ) -> QName.fromTuple ( moduleName, localName ))
            )
            basicsPendingSDK
            [ [ "basics" ] ]
        , listCheck "List SDK List = List SDK Implemented List"
            (SDK.packageSpec.modules
                |> Dict.toList
                |> List.map (\( moduleName, moduleSpec ) -> moduleSpec.values |> Dict.toList |> List.map (\a -> QName.fromTuple ( moduleName, Tuple.first a )))
                |> List.concat
            )
            (SDK.nativeFunctions
                |> Dict.toList
                |> List.map (\( ( _, moduleName, localName ), _ ) -> QName.fromTuple ( moduleName, localName ))
            )
            listPendingSDK
            [ [ "list" ] ]
        , listCheck "Tuple SDK List = Tuple SDK Implemented List"
            (SDK.packageSpec.modules
                |> Dict.toList
                |> List.map (\( moduleName, moduleSpec ) -> moduleSpec.values |> Dict.toList |> List.map (\a -> QName.fromTuple ( moduleName, Tuple.first a )))
                |> List.concat
            )
            (SDK.nativeFunctions
                |> Dict.toList
                |> List.map (\( ( _, moduleName, localName ), _ ) -> QName.fromTuple ( moduleName, localName ))
            )
            tuplePendingSDK
            [ [ "tuple" ] ]
        , listCheck "String SDK List = String SDK Implemented List"
            (SDK.packageSpec.modules
                |> Dict.toList
                |> List.map (\( moduleName, moduleSpec ) -> moduleSpec.values |> Dict.toList |> List.map (\a -> QName.fromTuple ( moduleName, Tuple.first a )))
                |> List.concat
            )
            (SDK.nativeFunctions
                |> Dict.toList
                |> List.map (\( ( _, moduleName, localName ), _ ) -> QName.fromTuple ( moduleName, localName ))
            )
            stringPendingSDK
            [ [ "string" ] ]
        , positiveCheck "(\\val1 val2 -> val1 + val2) 1 2"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Lambda ()
                        (Value.AsPattern () (Value.WildcardPattern ()) [ "val", "1" ])
                        (Value.Lambda ()
                            (Value.AsPattern () (Value.WildcardPattern ()) [ "val", "2" ])
                            (Value.Apply ()
                                (Value.Apply ()
                                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "add"))
                                    (Value.Variable () [ "val", "1" ])
                                )
                                (Value.Variable () [ "val", "2" ])
                            )
                        )
                    )
                    (Value.Literal () (WholeNumberLiteral 1))
                )
                (Value.Literal () (WholeNumberLiteral 2))
            )
            (Value.Literal () (WholeNumberLiteral 3))
        , {- Basics.always -}
          positiveCheck "List.map (always 0) [1,2,3] = [0,0,0]"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "map"))
                    (Value.Apply ()
                        (Value.Reference () (fqn "Morphir.SDK" "Basics" "always"))
                        (Value.Literal () (WholeNumberLiteral 0))
                    )
                )
                (Value.List () [ Value.Literal () (WholeNumberLiteral 1), Value.Literal () (WholeNumberLiteral 2), Value.Literal () (WholeNumberLiteral 3) ])
            )
            (Value.List () [ Value.Literal () (WholeNumberLiteral 0), Value.Literal () (WholeNumberLiteral 0), Value.Literal () (WholeNumberLiteral 0) ])
        , positiveCheck "List.isEmpty [] == True"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "List" "isEmpty"))
                (Value.List () [])
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck "List.isEmpty [1,2] == False"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "List" "isEmpty"))
                (Value.List () [ Value.Literal () (WholeNumberLiteral 1), Value.Literal () (WholeNumberLiteral 2) ])
            )
            (Value.Literal () (BoolLiteral False))
        , positiveCheck "List.head [] == Nothing"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "List" "head"))
                (Value.List () [])
            )
            (Value.Constructor () (fqn "Morphir.SDK" "Maybe" "Nothing"))
        , positiveCheck "List.head [[\"1\"],[\"2\"]] == Just [\"1\"]"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "List" "head"))
                (Value.List () [ Value.List () [ Value.Literal () (StringLiteral "1") ], Value.List () [ Value.Literal () (StringLiteral "2") ] ])
            )
            (Value.Apply () (Value.Constructor () (fqn "Morphir.SDK" "Maybe" "Just")) (Value.List () [ Value.Literal () (StringLiteral "1") ]))
        , positiveCheck "List.concat [[\"1\"],[\"2\"]] == [\"1\",\"2\"]"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "List" "concat"))
                (Value.List () [ Value.List () [ Value.Literal () (StringLiteral "1") ], Value.List () [ Value.Literal () (StringLiteral "2") ] ])
            )
            (Value.List () [ Value.Literal () (StringLiteral "1"), Value.Literal () (StringLiteral "2") ])

        --, positiveCheck "List.concatMap List [1,2] == [\"1\",\"2\"]"
        --    (Value.Apply ()
        --        (Value.Reference () (fqn "Morphir.SDK" "List" "concat"))
        --        (Value.List () [ Value.List () [ Value.Literal () (StringLiteral "1") ], Value.List () [ Value.Literal () (StringLiteral "2") ] ])
        --    )
        --    (Value.List () [ Value.Literal () (StringLiteral "1"), Value.Literal () (StringLiteral "2") ])
        , positiveCheck "List.intersperse 4 [2,3,5] == [2,4,3,4,5]"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "intersperse"))
                    (Value.Literal () (WholeNumberLiteral 4))
                )
                (Value.List () [ Value.Literal () (WholeNumberLiteral 2), Value.Literal () (WholeNumberLiteral 3), Value.Literal () (WholeNumberLiteral 5) ])
            )
            (Value.List () [ Value.Literal () (WholeNumberLiteral 2), Value.Literal () (WholeNumberLiteral 4), Value.Literal () (WholeNumberLiteral 3), Value.Literal () (WholeNumberLiteral 4), Value.Literal () (WholeNumberLiteral 5) ])
        , positiveCheck "List.filter  (\\value -> if modBy 2 value == 0 then True else False) [1,2,3,4] == [2,4] "
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "filter"))
                    (Value.Lambda ()
                        (Value.AsPattern () (Value.WildcardPattern ()) [ "value" ])
                        (Value.IfThenElse ()
                            (Value.Apply ()
                                (Value.Apply ()
                                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "equal"))
                                    (Value.Apply ()
                                        (Value.Apply ()
                                            (Value.Reference () (fqn "Morphir.SDK" "Basics" "modBy"))
                                            (Value.Literal () (WholeNumberLiteral 2))
                                        )
                                        (Value.Variable () [ "value" ])
                                    )
                                )
                                (Value.Literal () (WholeNumberLiteral 0))
                            )
                            (Value.Literal () (BoolLiteral True))
                            (Value.Literal () (BoolLiteral False))
                        )
                    )
                )
                (Value.List () [ Value.Literal () (WholeNumberLiteral 1), Value.Literal () (WholeNumberLiteral 2), Value.Literal () (WholeNumberLiteral 3), Value.Literal () (WholeNumberLiteral 4) ])
            )
            (Value.List () [ Value.Literal () (WholeNumberLiteral 2), Value.Literal () (WholeNumberLiteral 4) ])
        , positiveCheck "List.filterMap String.toInt [\"1\",\"hi\",\"3\",\"4\"] == [1,3,4]"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "filterMap"))
                    (Value.Lambda ()
                        (Value.AsPattern () (Value.WildcardPattern ()) [ "value" ])
                        (Value.Apply ()
                            (Value.Reference () (fqn "Morphir.SDK" "String" "toInt"))
                            (Value.Variable () [ "value" ])
                        )
                    )
                )
                (Value.List () [ Value.Literal () (StringLiteral "1"), Value.Literal () (StringLiteral "hi"), Value.Literal () (StringLiteral "3"), Value.Literal () (StringLiteral "4") ])
            )
            (Value.List () [ Value.Literal () (WholeNumberLiteral 1), Value.Literal () (WholeNumberLiteral 3), Value.Literal () (WholeNumberLiteral 4) ])
        , positiveCheck "List.filterMap String.toInt [\"hi\",\"hello\"] == []"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "filterMap"))
                    (Value.Lambda ()
                        (Value.AsPattern () (Value.WildcardPattern ()) [ "value" ])
                        (Value.Apply ()
                            (Value.Reference () (fqn "Morphir.SDK" "String" "toInt"))
                            (Value.Variable () [ "value" ])
                        )
                    )
                )
                (Value.List () [ Value.Literal () (StringLiteral "hi"), Value.Literal () (StringLiteral "hello") ])
            )
            (Value.List () [])
        , positiveCheck "List.all (\\value -> if modBy 2 value == 0 then True else False) [2,4,6]"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "all"))
                    (Value.Lambda ()
                        (Value.AsPattern () (Value.WildcardPattern ()) [ "value" ])
                        (Value.IfThenElse ()
                            (Value.Apply ()
                                (Value.Apply ()
                                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "equal"))
                                    (Value.Apply ()
                                        (Value.Apply ()
                                            (Value.Reference () (fqn "Morphir.SDK" "Basics" "modBy"))
                                            (Value.Literal () (WholeNumberLiteral 2))
                                        )
                                        (Value.Variable () [ "value" ])
                                    )
                                )
                                (Value.Literal () (WholeNumberLiteral 0))
                            )
                            (Value.Literal () (BoolLiteral True))
                            (Value.Literal () (BoolLiteral False))
                        )
                    )
                )
                (Value.List () [ Value.Literal () (WholeNumberLiteral 2), Value.Literal () (WholeNumberLiteral 4), Value.Literal () (WholeNumberLiteral 6) ])
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck "List.any (\\value -> if modBy 2 value == 0 then True else False) [1,2,3]"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "any"))
                    (Value.Lambda ()
                        (Value.AsPattern () (Value.WildcardPattern ()) [ "value" ])
                        (Value.IfThenElse ()
                            (Value.Apply ()
                                (Value.Apply ()
                                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "equal"))
                                    (Value.Apply ()
                                        (Value.Apply ()
                                            (Value.Reference () (fqn "Morphir.SDK" "Basics" "modBy"))
                                            (Value.Literal () (WholeNumberLiteral 2))
                                        )
                                        (Value.Variable () [ "value" ])
                                    )
                                )
                                (Value.Literal () (WholeNumberLiteral 0))
                            )
                            (Value.Literal () (BoolLiteral True))
                            (Value.Literal () (BoolLiteral False))
                        )
                    )
                )
                (Value.List () [ Value.Literal () (WholeNumberLiteral 1), Value.Literal () (WholeNumberLiteral 2), Value.Literal () (WholeNumberLiteral 3) ])
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck "List.any (\\value -> if modBy 2 value == 0 then True else False) [1,3]"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "any"))
                    (Value.Lambda ()
                        (Value.AsPattern () (Value.WildcardPattern ()) [ "value" ])
                        (Value.IfThenElse ()
                            (Value.Apply ()
                                (Value.Apply ()
                                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "equal"))
                                    (Value.Apply ()
                                        (Value.Apply ()
                                            (Value.Reference () (fqn "Morphir.SDK" "Basics" "modBy"))
                                            (Value.Literal () (WholeNumberLiteral 2))
                                        )
                                        (Value.Variable () [ "value" ])
                                    )
                                )
                                (Value.Literal () (WholeNumberLiteral 0))
                            )
                            (Value.Literal () (BoolLiteral True))
                            (Value.Literal () (BoolLiteral False))
                        )
                    )
                )
                (Value.List () [ Value.Literal () (WholeNumberLiteral 1), Value.Literal () (WholeNumberLiteral 3) ])
            )
            (Value.Literal () (BoolLiteral False))
        , {- Basics.identity -}
          positiveCheck "identity 5 = 5"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "identity"))
                (Value.Literal () (WholeNumberLiteral 5))
            )
            (Value.Literal () (WholeNumberLiteral 5))
        , positiveCheck "identity [\"a\",\"b\",\"123\"] = [\"a\",\"b\",\"123\"]"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "identity"))
                (Value.List () [ Value.Literal () (StringLiteral "a"), Value.Literal () (StringLiteral "b"), Value.Literal () (StringLiteral "123") ])
            )
            (Value.List () [ Value.Literal () (StringLiteral "a"), Value.Literal () (StringLiteral "b"), Value.Literal () (StringLiteral "123") ])
        , {- Basics.equal -}
          positiveCheck "True = True"
            (Value.Literal () (BoolLiteral True))
            (Value.Literal () (BoolLiteral True))

        {- Basics.not -}
        , positiveCheck "not True == False"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "not"))
                (Value.Literal () (BoolLiteral True))
            )
            (Value.Literal () (BoolLiteral False))

        {- Basics.and -}
        , positiveCheck "True && False == False"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "and"))
                    (Value.Literal () (BoolLiteral True))
                )
                (Value.Literal () (BoolLiteral False))
            )
            (Value.Literal () (BoolLiteral False))
        , positiveCheck "False && True == False"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "and"))
                    (Value.Literal () (BoolLiteral False))
                )
                (Value.Literal () (BoolLiteral True))
            )
            (Value.Literal () (BoolLiteral False))

        {- Basics.add -}
        , positiveCheck "2 + 4 == 6"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "add"))
                    (Value.Literal () (WholeNumberLiteral 2))
                )
                (Value.Literal () (WholeNumberLiteral 4))
            )
            (Value.Literal () (WholeNumberLiteral 6))
        , positiveCheck "6.2 + 4.8 == 11"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "add"))
                    (Value.Literal () (FloatLiteral 6.2))
                )
                (Value.Literal () (FloatLiteral 4.8))
            )
            (Value.Literal () (FloatLiteral 11))
        , positiveCheck "1000000000000 + 2000000000000 == 3000000000000"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "add"))
                    (Value.Literal () (WholeNumberLiteral 1000000000000))
                )
                (Value.Literal () (WholeNumberLiteral 2000000000000))
            )
            (Value.Literal () (WholeNumberLiteral 3000000000000))
        , positiveCheck "2 + 4.2 == 6.2"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "add"))
                    (Value.Literal () (FloatLiteral 2))
                )
                (Value.Literal () (FloatLiteral 4.2))
            )
            (Value.Literal () (FloatLiteral 6.2))
        , positiveCheck "10.5 + 3 == 13.5"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "add"))
                    (Value.Literal () (FloatLiteral 10.5))
                )
                (Value.Literal () (FloatLiteral 3))
            )
            (Value.Literal () (FloatLiteral 13.5))

        {- Basics.subtract -}
        , positiveCheck "1000000000000 - 1000000000000 == 0"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "subtract"))
                    (Value.Literal () (WholeNumberLiteral 1000000000000))
                )
                (Value.Literal () (WholeNumberLiteral 1000000000000))
            )
            (Value.Literal () (WholeNumberLiteral 0))
        , positiveCheck " 100 - 0.4 == 99.6"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "subtract"))
                    (Value.Literal () (FloatLiteral 100))
                )
                (Value.Literal () (FloatLiteral 0.4))
            )
            (Value.Literal () (FloatLiteral 99.6))
        , positiveCheck " 17 - 0.8 == 16.2"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "subtract"))
                    (Value.Literal () (FloatLiteral 17))
                )
                (Value.Literal () (FloatLiteral 0.8))
            )
            (Value.Literal () (FloatLiteral 16.2))
        , positiveCheck " 30.6 - 2 == 28.6"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "subtract"))
                    (Value.Literal () (FloatLiteral 30.6))
                )
                (Value.Literal () (FloatLiteral 2))
            )
            (Value.Literal () (FloatLiteral 28.6))

        {- Basics.multiply -}
        , positiveCheck " 0.4 mul 5.0 == 2.0"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "multiply"))
                    (Value.Literal () (FloatLiteral 0.4))
                )
                (Value.Literal () (FloatLiteral 5))
            )
            (Value.Literal () (FloatLiteral 2))
        , positiveCheck " 3 mul 5 == 15"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "multiply"))
                    (Value.Literal () (WholeNumberLiteral 3))
                )
                (Value.Literal () (WholeNumberLiteral 5))
            )
            (Value.Literal () (WholeNumberLiteral 15))
        , positiveCheck " 10 mul 5.0 == 50.0"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "multiply"))
                    (Value.Literal () (FloatLiteral 10))
                )
                (Value.Literal () (FloatLiteral 5))
            )
            (Value.Literal () (FloatLiteral 50))
        , positiveCheck " 30.2 mul 5 == 151.0"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "multiply"))
                    (Value.Literal () (FloatLiteral 30.2))
                )
                (Value.Literal () (FloatLiteral 5))
            )
            (Value.Literal () (FloatLiteral 151))

        {- Basics.divide -}
        , positiveCheck "4.0 / 2.0 == 2.0"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "divide"))
                    (Value.Literal () (FloatLiteral 4))
                )
                (Value.Literal () (FloatLiteral 2))
            )
            (Value.Literal () (FloatLiteral 2))
        , positiveCheck "2.0 / 5.0 == 0.4"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "divide"))
                    (Value.Literal () (FloatLiteral 2))
                )
                (Value.Literal () (FloatLiteral 5))
            )
            (Value.Literal () (FloatLiteral 0.4))
        , positiveCheck "7.5 / 0.0 == Infinite"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "divide"))
                    (Value.Literal () (FloatLiteral 7.5))
                )
                (Value.Literal () (FloatLiteral 0))
            )
            (Value.Literal () (FloatLiteral (1 / 0)))
        , positiveCheck "1.0 / 10.0 == 0.1"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "divide"))
                    (Value.Literal () (FloatLiteral 1.0))
                )
                (Value.Literal () (FloatLiteral 10.0))
            )
            (Value.Literal () (FloatLiteral 0.1))

        {- Basics.lessThan -}
        , positiveCheck " 100 < 100 == False"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThan"))
                    (Value.Literal () (WholeNumberLiteral 100))
                )
                (Value.Literal () (WholeNumberLiteral 100))
            )
            (Value.Literal () (BoolLiteral False))
        , positiveCheck " -10.0 < -100.0 == False"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThan"))
                    (Value.Literal () (FloatLiteral -10))
                )
                (Value.Literal () (FloatLiteral -100))
            )
            (Value.Literal () (BoolLiteral False))
        , positiveCheck " 10 < -100 == False"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThan"))
                    (Value.Literal () (WholeNumberLiteral 10))
                )
                (Value.Literal () (WholeNumberLiteral -100))
            )
            (Value.Literal () (BoolLiteral False))
        , positiveCheck " 10.6 < -10.2 == False"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThan"))
                    (Value.Literal () (FloatLiteral 10.6))
                )
                (Value.Literal () (FloatLiteral -10.2))
            )
            (Value.Literal () (BoolLiteral False))
        , positiveCheck " 10.111 < 10.112  == True"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThan"))
                    (Value.Literal () (FloatLiteral 10.111))
                )
                (Value.Literal () (FloatLiteral 10.112))
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck " 5 < 2.5 == False"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThan"))
                    (Value.Literal () (FloatLiteral 5))
                )
                (Value.Literal () (FloatLiteral 2.5))
            )
            (Value.Literal () (BoolLiteral False))
        , positiveCheck " 10.111 < 12  == True"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThan"))
                    (Value.Literal () (FloatLiteral 10.111))
                )
                (Value.Literal () (FloatLiteral 12))
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck " 'a' < 'c'  == True"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThan"))
                    (Value.Literal () (CharLiteral 'a'))
                )
                (Value.Literal () (CharLiteral 'c'))
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck " 'a' < 'a'  == False"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThan"))
                    (Value.Literal () (CharLiteral 'a'))
                )
                (Value.Literal () (CharLiteral 'a'))
            )
            (Value.Literal () (BoolLiteral False))
        , positiveCheck " 'z' < 'a'  == False"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThan"))
                    (Value.Literal () (CharLiteral 'z'))
                )
                (Value.Literal () (CharLiteral 'a'))
            )
            (Value.Literal () (BoolLiteral False))
        , positiveCheck " \"ball\" < \"bool\"  == True"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThan"))
                    (Value.Literal () (StringLiteral "ball"))
                )
                (Value.Literal () (StringLiteral "bool"))
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck " \"ball\" < \"ball\"  == False"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThan"))
                    (Value.Literal () (StringLiteral "ball"))
                )
                (Value.Literal () (StringLiteral "ball"))
            )
            (Value.Literal () (BoolLiteral False))

        {- Basics.cos -}
        , positiveCheck "cos(degree 60) == 0.5000000000000001"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "cos"))
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "degrees"))
                    (Value.Literal () (FloatLiteral 60))
                )
            )
            (Value.Literal () (FloatLiteral 0.5000000000000001))
        , positiveCheck "cos(turns 1/6) == 0.5000000000000001"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "cos"))
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "turns"))
                    (Value.Apply ()
                        (Value.Apply ()
                            (Value.Reference () (fqn "Morphir.SDK" "Basics" "divide"))
                            (Value.Literal () (FloatLiteral 1))
                        )
                        (Value.Literal () (FloatLiteral 6))
                    )
                )
            )
            (Value.Literal () (FloatLiteral 0.5000000000000001))
        , positiveCheck "cos(radians (pi/3)) == 0.5000000000000001"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "cos"))
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "radians"))
                    (Value.Apply ()
                        (Value.Apply ()
                            (Value.Reference () (fqn "Morphir.SDK" "Basics" "divide"))
                            (Value.Reference () (fqn "Morphir.SDK" "Basics" "pi"))
                        )
                        (Value.Literal () (FloatLiteral 3))
                    )
                )
            )
            (Value.Literal () (FloatLiteral 0.5000000000000001))
        , positiveCheck "cos(pi/3) == 0.5000000000000001"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "cos"))
                (Value.Apply ()
                    (Value.Apply ()
                        (Value.Reference () (fqn "Morphir.SDK" "Basics" "divide"))
                        (Value.Reference () (fqn "Morphir.SDK" "Basics" "pi"))
                    )
                    (Value.Literal () (FloatLiteral 3))
                )
            )
            (Value.Literal () (FloatLiteral 0.5000000000000001))

        {- Basics.pi -}
        , positiveCheck "pi == pi"
            (Value.Reference () (fqn "Morphir.SDK" "Basics" "pi"))
            (Value.Literal () (FloatLiteral 3.141592653589793))

        {- Basics.floor -}
        , positiveCheck "floor(4.99999999999999) == 4"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "floor"))
                (Value.Literal () (FloatLiteral 4.99999999999999))
            )
            (Value.Literal () (WholeNumberLiteral 4))
        , positiveCheck "floor(-4.000001) == -5"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "floor"))
                (Value.Literal () (FloatLiteral -4.000001))
            )
            (Value.Literal () (WholeNumberLiteral -5))
        , positiveCheck "floor(4.00000001) == 4"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "floor"))
                (Value.Literal () (FloatLiteral 4.00000001))
            )
            (Value.Literal () (WholeNumberLiteral 4))

        {- Basics.ceiling -}
        , positiveCheck "ceiling(4.000000001) == 5"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "ceiling"))
                (Value.Literal () (FloatLiteral 4.000000001))
            )
            (Value.Literal () (WholeNumberLiteral 5))
        , positiveCheck "ceiling(4.9999999999) == 5"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "ceiling"))
                (Value.Literal () (FloatLiteral 4.9999999999))
            )
            (Value.Literal () (WholeNumberLiteral 5))
        , positiveCheck "ceiling(-3.000000000001) == -3"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "ceiling"))
                (Value.Literal () (FloatLiteral -3.000000000001))
            )
            (Value.Literal () (WholeNumberLiteral -3))

        {- Basics.isNan -}
        , positiveCheck "isNaN(4.0001) == False"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "isNaN"))
                (Value.Literal () (FloatLiteral 4.0001))
            )
            (Value.Literal () (BoolLiteral False))
        , positiveCheck "isNaN(1/0) == False"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "isNaN"))
                (Value.Apply ()
                    (Value.Apply ()
                        (Value.Reference () (fqn "Morphir.SDK" "Basics" "divide"))
                        (Value.Literal () (FloatLiteral 1))
                    )
                    (Value.Literal () (FloatLiteral 0))
                )
            )
            (Value.Literal () (BoolLiteral False))
        , positiveCheck "isNaN(0/0) == True"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "isNaN"))
                (Value.Apply ()
                    (Value.Apply ()
                        (Value.Reference () (fqn "Morphir.SDK" "Basics" "divide"))
                        (Value.Literal () (FloatLiteral 0))
                    )
                    (Value.Literal () (FloatLiteral 0))
                )
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck "isNaN( sqrt -1) == True"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "isNaN"))
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "sqrt"))
                    (Value.Literal () (FloatLiteral -1))
                )
            )
            (Value.Literal () (BoolLiteral True))

        {- Basics.sqrt -}
        , positiveCheck "sqrt 16 == 4"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "sqrt"))
                (Value.Literal () (FloatLiteral 16))
            )
            (Value.Literal () (FloatLiteral 4))
        , positiveCheck "sqrt 10 == 3.1622776601683795"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "Basics" "sqrt"))
                (Value.Literal () (FloatLiteral 10))
            )
            (Value.Literal () (FloatLiteral 3.1622776601683795))

        {- Basics.lessThanEqualTo -}
        , positiveCheck " -10.0 <= -100.0 == False"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThanOrEqual"))
                    (Value.Literal () (FloatLiteral -10))
                )
                (Value.Literal () (FloatLiteral -100))
            )
            (Value.Literal () (BoolLiteral False))
        , positiveCheck " 10 <= -100 == False"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThanOrEqual"))
                    (Value.Literal () (WholeNumberLiteral 10))
                )
                (Value.Literal () (WholeNumberLiteral -100))
            )
            (Value.Literal () (BoolLiteral False))
        , positiveCheck " 10.6 <= -10.2 == False"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThanOrEqual"))
                    (Value.Literal () (FloatLiteral 10.6))
                )
                (Value.Literal () (FloatLiteral -10.2))
            )
            (Value.Literal () (BoolLiteral False))
        , positiveCheck " 10.111 <= 10.112  == True"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThanOrEqual"))
                    (Value.Literal () (FloatLiteral 10.111))
                )
                (Value.Literal () (FloatLiteral 10.112))
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck " 'a' <= 'c'  == True"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThanOrEqual"))
                    (Value.Literal () (CharLiteral 'a'))
                )
                (Value.Literal () (CharLiteral 'c'))
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck " 'z' <= 'a'  == False"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThanOrEqual"))
                    (Value.Literal () (CharLiteral 'z'))
                )
                (Value.Literal () (CharLiteral 'a'))
            )
            (Value.Literal () (BoolLiteral False))
        , positiveCheck " \"ball\" <= \"bool\"  == True"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThanOrEqual"))
                    (Value.Literal () (StringLiteral "ball"))
                )
                (Value.Literal () (StringLiteral "bool"))
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck " -10.0 >= -100.0 == True"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "greaterThanOrEqual"))
                    (Value.Literal () (FloatLiteral -10.0))
                )
                (Value.Literal () (FloatLiteral -100.0))
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck " -100 >= 10 == False"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "greaterThanOrEqual"))
                    (Value.Literal () (WholeNumberLiteral -100))
                )
                (Value.Literal () (WholeNumberLiteral 10))
            )
            (Value.Literal () (BoolLiteral False))
        , {- Basics.greaterThanEqualTo -}
          positiveCheck "value >= 46 == True"
            (Value.Apply ()
                (Value.Lambda
                    ()
                    (Value.AsPattern () (Value.WildcardPattern ()) [ "value" ])
                    (Value.Apply ()
                        (Value.Apply ()
                            (Value.Reference () (fqn "Morphir.SDK" "Basics" "greaterThanOrEqual"))
                            (Value.Literal () (WholeNumberLiteral 46))
                        )
                        (Value.Variable () [ "value" ])
                    )
                )
                (Value.Literal () (WholeNumberLiteral 20))
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck " -10.2 >= -10.6 == True"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "greaterThanOrEqual"))
                    (Value.Literal () (FloatLiteral 10.2))
                )
                (Value.Literal () (FloatLiteral -10.6))
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck " 10.112 >= 10.111  == True"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "greaterThanOrEqual"))
                    (Value.Literal () (FloatLiteral 10.112))
                )
                (Value.Literal () (FloatLiteral 10.111))
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck " 'c' >= 'a' == True"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "greaterThanOrEqual"))
                    (Value.Literal () (CharLiteral 'c'))
                )
                (Value.Literal () (CharLiteral 'a'))
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck " 'a' >= 'z' == False"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "greaterThanOrEqual"))
                    (Value.Literal () (CharLiteral 'a'))
                )
                (Value.Literal () (CharLiteral 'z'))
            )
            (Value.Literal () (BoolLiteral False))
        , positiveCheck " \"bool\" >= \"ball\"  == True"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "greaterThanOrEqual"))
                    (Value.Literal () (StringLiteral "bool"))
                )
                (Value.Literal () (StringLiteral "ball"))
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck " 100 >= 100 == True"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "greaterThanOrEqual"))
                    (Value.Literal () (WholeNumberLiteral 100))
                )
                (Value.Literal () (WholeNumberLiteral 100))
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck " 10.112 >= 10.112  == True"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "greaterThanOrEqual"))
                    (Value.Literal () (FloatLiteral 10.112))
                )
                (Value.Literal () (FloatLiteral 10.112))
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck " 'a' >= 'a'  == True"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "greaterThanOrEqual"))
                    (Value.Literal () (CharLiteral 'a'))
                )
                (Value.Literal () (CharLiteral 'a'))
            )
            (Value.Literal () (BoolLiteral True))
        , positiveCheck " \"ball\" >= \"ball\"  == True"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "greaterThanOrEqual"))
                    (Value.Literal () (StringLiteral "ball"))
                )
                (Value.Literal () (StringLiteral "ball"))
            )
            (Value.Literal () (BoolLiteral True))

        {- List.sum -}
        , positiveCheck " sum [1,3]  == 4"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "List" "sum"))
                (Value.List () [ Value.Literal () (WholeNumberLiteral 1), Value.Literal () (WholeNumberLiteral 3) ])
            )
            (Value.Literal () (WholeNumberLiteral 4))
        , positiveCheck " sum [1,-1]  == 0"
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "List" "sum"))
                (Value.List () [ Value.Literal () (WholeNumberLiteral 1), Value.Literal () (WholeNumberLiteral -1) ])
            )
            (Value.Literal () (WholeNumberLiteral 0))

        {- List.append -}
        , positiveCheck " append [1,2,3] [1,2] == [1,2,3,1,2]"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "append"))
                    (Value.List () [ Value.Literal () (WholeNumberLiteral 1), Value.Literal () (WholeNumberLiteral 2), Value.Literal () (WholeNumberLiteral 3) ])
                )
                (Value.List () [ Value.Literal () (WholeNumberLiteral 1), Value.Literal () (WholeNumberLiteral 2) ])
            )
            (Value.List () [ Value.Literal () (WholeNumberLiteral 1), Value.Literal () (WholeNumberLiteral 2), Value.Literal () (WholeNumberLiteral 3), Value.Literal () (WholeNumberLiteral 1), Value.Literal () (WholeNumberLiteral 2) ])
        , positiveCheck " append [1,2,3] [] == [1,2,3]"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "append"))
                    (Value.List () [ Value.Literal () (WholeNumberLiteral 1), Value.Literal () (WholeNumberLiteral 2), Value.Literal () (WholeNumberLiteral 3) ])
                )
                (Value.List () [])
            )
            (Value.List () [ Value.Literal () (WholeNumberLiteral 1), Value.Literal () (WholeNumberLiteral 2), Value.Literal () (WholeNumberLiteral 3) ])
        , positiveCheck " append [] [1,2] == [1,2]"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "append"))
                    (Value.List () [])
                )
                (Value.List () [ Value.Literal () (WholeNumberLiteral 1), Value.Literal () (WholeNumberLiteral 2) ])
            )
            (Value.List () [ Value.Literal () (WholeNumberLiteral 1), Value.Literal () (WholeNumberLiteral 2) ])
        , positiveCheck " append [] [] == []"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "append"))
                    (Value.List () [])
                )
                (Value.List () [])
            )
            (Value.List () [])
        , positiveCheck " append [True, False] [False,True] == [True, False,False,True]"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "append"))
                    (Value.List () [ Value.Literal () (BoolLiteral True), Value.Literal () (BoolLiteral False) ])
                )
                (Value.List () [ Value.Literal () (BoolLiteral False), Value.Literal () (BoolLiteral True) ])
            )
            (Value.List () [ Value.Literal () (BoolLiteral True), Value.Literal () (BoolLiteral False), Value.Literal () (BoolLiteral False), Value.Literal () (BoolLiteral True) ])
        , positiveCheck " append ['a','b'] ['c'] == ['a','b','c']"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "append"))
                    (Value.List () [ Value.Literal () (CharLiteral 'a'), Value.Literal () (CharLiteral 'b') ])
                )
                (Value.List () [ Value.Literal () (CharLiteral 'c') ])
            )
            (Value.List () [ Value.Literal () (CharLiteral 'a'), Value.Literal () (CharLiteral 'b'), Value.Literal () (CharLiteral 'c') ])
        , positiveCheck " append [\"Hello\",\"World\"] [\"Happy\", \"?\"] == [\"Hello\",\"World\",\"Happy\", \"?\"]"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "append"))
                    (Value.List () [ Value.Literal () (StringLiteral "Hello"), Value.Literal () (StringLiteral "World") ])
                )
                (Value.List () [ Value.Literal () (StringLiteral "Happy"), Value.Literal () (StringLiteral "?") ])
            )
            (Value.List () [ Value.Literal () (StringLiteral "Hello"), Value.Literal () (StringLiteral "World"), Value.Literal () (StringLiteral "Happy"), Value.Literal () (StringLiteral "?") ])
        , positiveCheck " append [9,0,8,10] [1,5,3,9,6] == [9,0,8,10,1,5,3,9,6]"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "append"))
                    (Value.List ()
                        [ Value.Literal () (WholeNumberLiteral 9)
                        , Value.Literal () (WholeNumberLiteral 0)
                        , Value.Literal () (WholeNumberLiteral 8)
                        , Value.Literal () (WholeNumberLiteral 10)
                        ]
                    )
                )
                (Value.List ()
                    [ Value.Literal () (WholeNumberLiteral 1)
                    , Value.Literal () (WholeNumberLiteral 5)
                    , Value.Literal () (WholeNumberLiteral 3)
                    , Value.Literal () (WholeNumberLiteral 9)
                    , Value.Literal () (WholeNumberLiteral 6)
                    ]
                )
            )
            (Value.List () [ Value.Literal () (WholeNumberLiteral 9), Value.Literal () (WholeNumberLiteral 0), Value.Literal () (WholeNumberLiteral 8), Value.Literal () (WholeNumberLiteral 10), Value.Literal () (WholeNumberLiteral 1), Value.Literal () (WholeNumberLiteral 5), Value.Literal () (WholeNumberLiteral 3), Value.Literal () (WholeNumberLiteral 9), Value.Literal () (WholeNumberLiteral 6) ])

        {- String.concat -}
        , positiveCheck " concat [\"a\",\"b\",\"123\"] == \"ab123\""
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "String" "concat"))
                (Value.List () [ Value.Literal () (StringLiteral "a"), Value.Literal () (StringLiteral "b"), Value.Literal () (StringLiteral "123") ])
            )
            (Value.Literal () (StringLiteral "ab123"))
        , positiveCheck " concat [] == \"\""
            (Value.Apply ()
                (Value.Reference () (fqn "Morphir.SDK" "String" "concat"))
                (Value.List () [])
            )
            (Value.Literal () (StringLiteral ""))

        {- Basics.lessThan -}
        , positiveCheck "if 100 < 1000 then 2 else 3"
            (Value.IfThenElse ()
                (Value.Apply ()
                    (Value.Apply ()
                        (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThan"))
                        (Value.Literal () (WholeNumberLiteral 100))
                    )
                    (Value.Literal () (WholeNumberLiteral 1000))
                )
                (Value.Literal () (WholeNumberLiteral 2))
                (Value.Literal () (WholeNumberLiteral 3))
            )
            (Value.Literal () (WholeNumberLiteral 2))
        , positiveCheck "if 1000 < 100 then 2 else 3"
            (Value.IfThenElse ()
                (Value.Apply ()
                    (Value.Apply ()
                        (Value.Reference () (fqn "Morphir.SDK" "Basics" "lessThan"))
                        (Value.Literal () (WholeNumberLiteral 1000))
                    )
                    (Value.Literal () (WholeNumberLiteral 100))
                )
                (Value.Literal () (WholeNumberLiteral 2))
                (Value.Literal () (WholeNumberLiteral 3))
            )
            (Value.Literal () (WholeNumberLiteral 3))

        {- List.map -}
        , positiveCheck "map (\\a -> a//2)  [2,4,6] = [1,2,3]"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "map"))
                    (Value.Lambda ()
                        (Value.AsPattern () (Value.WildcardPattern ()) [ "a" ])
                        (Value.Apply ()
                            (Value.Apply ()
                                (Value.Reference () (fqn "Morphir.SDK" "Basics" "integerDivide"))
                                (Value.Variable () [ "a" ])
                            )
                            (Value.Literal () (WholeNumberLiteral 2))
                        )
                    )
                )
                (Value.List () [ Value.Literal () (WholeNumberLiteral 2), Value.Literal () (WholeNumberLiteral 4), Value.Literal () (WholeNumberLiteral 6) ])
            )
            (Value.List () [ Value.Literal () (WholeNumberLiteral 1), Value.Literal () (WholeNumberLiteral 2), Value.Literal () (WholeNumberLiteral 3) ])
        , {- modBy 2 value = 1 -}
          positiveCheck "modBy 2 value = 1 "
            (Value.Apply ()
                (Value.Lambda
                    ()
                    (Value.AsPattern () (Value.WildcardPattern ()) [ "value" ])
                    (Value.Apply ()
                        (Value.Apply ()
                            (Value.Reference () (fqn "Morphir.SDK" "Basics" "modBy"))
                            (Value.Literal () (WholeNumberLiteral 2))
                        )
                        (Value.Variable () [ "value" ])
                    )
                )
                (Value.Literal () (WholeNumberLiteral 5))
            )
            (Value.Literal () (WholeNumberLiteral 1))
        , positiveCheck " (\\value -> if modBy 2 value == 0 then True else False) "
            (Value.Apply ()
                (Value.Lambda ()
                    (Value.AsPattern () (Value.WildcardPattern ()) [ "value" ])
                    (Value.IfThenElse ()
                        (Value.Apply ()
                            (Value.Apply ()
                                (Value.Reference () (fqn "Morphir.SDK" "Basics" "equal"))
                                (Value.Apply ()
                                    (Value.Apply ()
                                        (Value.Reference () (fqn "Morphir.SDK" "Basics" "modBy"))
                                        (Value.Literal () (WholeNumberLiteral 2))
                                    )
                                    (Value.Variable () [ "value" ])
                                )
                            )
                            (Value.Literal () (WholeNumberLiteral 0))
                        )
                        (Value.Literal () (BoolLiteral True))
                        (Value.Literal () (BoolLiteral False))
                    )
                )
                (Value.Literal () (WholeNumberLiteral 5))
            )
            (Value.Literal () (BoolLiteral False))

        {- List.map (modBy) -}
        , positiveCheck "map (modBy 4)  [-5,0,5] = [3,0,1]"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "map"))
                    (Value.Apply ()
                        (Value.Reference () (fqn "Morphir.SDK" "Basics" "modBy"))
                        (Value.Literal () (WholeNumberLiteral 4))
                    )
                )
                (Value.List () [ Value.Literal () (WholeNumberLiteral -5), Value.Literal () (WholeNumberLiteral 0), Value.Literal () (WholeNumberLiteral 5) ])
            )
            (Value.List () [ Value.Literal () (WholeNumberLiteral 3), Value.Literal () (WholeNumberLiteral 0), Value.Literal () (WholeNumberLiteral 1) ])

        {- List.map (not) -}
        , positiveCheck
            "map not [True,False,True] = [False,True,False]"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "map"))
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "not"))
                )
                (Value.List () [ Value.Literal () (BoolLiteral True), Value.Literal () (BoolLiteral False), Value.Literal () (BoolLiteral True) ])
            )
            (Value.List () [ Value.Literal () (BoolLiteral False), Value.Literal () (BoolLiteral True), Value.Literal () (BoolLiteral False) ])

        {- List.map (lambda) -}
        , positiveCheck "map (\\a -> -a)  [2,4,6] = [-2,-4,-6]"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "map"))
                    (Value.Lambda ()
                        (Value.AsPattern () (Value.WildcardPattern ()) [ "a" ])
                        (Value.Apply ()
                            (Value.Apply ()
                                (Value.Reference () (fqn "Morphir.SDK" "Basics" "subtract"))
                                (Value.Literal () (WholeNumberLiteral 0))
                            )
                            (Value.Variable () [ "a" ])
                        )
                    )
                )
                (Value.List () [ Value.Literal () (WholeNumberLiteral 2), Value.Literal () (WholeNumberLiteral 4), Value.Literal () (WholeNumberLiteral 6) ])
            )
            (Value.List () [ Value.Literal () (WholeNumberLiteral -2), Value.Literal () (WholeNumberLiteral -4), Value.Literal () (WholeNumberLiteral -6) ])
        ]
