{-
Copyright 2020 Morgan Stanley

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}


module SlateX.DevBot.Scala.SlateXToScala.CoreValues exposing (mapApply, mapConstructor, mapMatchConstructor, mapReference, mapXToFlatMap, maybeMapApply, maybeMapConstructor, maybeMapReference)

import SlateX.DevBot.Scala.AST as S
import SlateX.DevBot.Scala.SlateXToScala.Report as Report


mapReference : String -> String -> S.Value
mapReference moduleName funName =
    maybeMapReference moduleName funName
        |> Maybe.withDefault
            (Report.todoValue ("Missing mapping for reference 'SlateX.Core." ++ moduleName ++ "." ++ funName ++ "'."))


maybeMapReference : String -> String -> Maybe S.Value
maybeMapReference moduleName funName =
    case moduleName of
        "Annotation" ->
            case funName of
                "undefined" ->
                    Just (Report.todoValue "This value is marked as 'undefined' in the model.")

                _ ->
                    Nothing

        "Basics" ->
            case funName of
                -- KNOWLEDGE: Elm's `Basics.identity` function maps directly to Scala's `Predef.identity` function.
                "identity" ->
                    Just (S.Ref [ "scala", "Predef" ] "identity")

                _ ->
                    Nothing

        "Dict" ->
            case funName of
                -- KNOWLEDGE: Elm's `Dict.empty` function maps to Scala's `Map.empty` function.
                "empty" ->
                    Just (S.Ref [ "scala", "Predef", "Map" ] "empty")

                _ ->
                    Nothing

        _ ->
            Nothing


mapApply : String -> String -> List S.Value -> S.Value
mapApply moduleName funName scalaArgs =
    maybeMapApply moduleName funName scalaArgs
        |> Maybe.withDefault
            (Report.todoValue ("Missing mapping for apply 'SlateX.Core." ++ moduleName ++ "." ++ funName ++ "' and args [ " ++ (scalaArgs |> List.map Debug.toString |> String.join ", ") ++ " ]."))


maybeMapApply : String -> String -> List S.Value -> Maybe S.Value
maybeMapApply moduleName funName scalaArgs =
    let
        curry : S.Value -> List S.Value -> S.Value
        curry fun argsReversed =
            case argsReversed of
                [] ->
                    fun

                lastArg :: initArgsReversed ->
                    S.Apply (curry fun initArgsReversed) [ S.ArgValue Nothing lastArg ]

        call : String -> String -> List S.Value -> Maybe S.Value
        call mod fun args =
            curry (S.Ref [ "morphir", "sdk", mod ] fun) (args |> List.reverse)
                |> Just
    in
    case moduleName of
        "Annotation" ->
            case ( funName, scalaArgs ) of
                ( "inverseOf", _ ) ->
                    Just (Report.todoValue "This value is marked as 'inverseOf' in the model.")

                ( "inversesOf", _ ) ->
                    Just (Report.todoValue "This value is marked as 'inversesOf' in the model.")

                ( "maybeInverseOf", _ ) ->
                    Just (Report.todoValue "This value is marked as 'maybeInverseOf' in the model.")

                _ ->
                    Nothing

        "Basics" ->
            case scalaArgs of
                [ arg ] ->
                    case funName of
                        "toDecimal" ->
                            Just <|
                                S.Apply (S.Ref [ "scala", "math" ] "BigDecimal")
                                    [ S.ArgValue Nothing arg
                                    , S.ArgValue Nothing (S.Ref [ "java", "math", "MathContext" ] "UNLIMITED")
                                    ]

                        "Debug.toString" ->
                            Just <|
                                S.Select arg "Debug.toString"

                        "round" ->
                            Just <|
                                S.Apply (S.Select arg "setScale")
                                    [ S.ArgValue Nothing (S.Literal (S.IntegerLit 0))
                                    , S.ArgValue Nothing (S.Ref [ "scala", "math", "BigDecimal", "RoundingMode" ] "HALF_UP")
                                    ]

                        "floor" ->
                            Just <|
                                S.Apply (S.Select arg "setScale")
                                    [ S.ArgValue Nothing (S.Literal (S.IntegerLit 0))
                                    , S.ArgValue Nothing (S.Ref [ "scala", "math", "BigDecimal", "RoundingMode" ] "FLOOR")
                                    ]

                        "ceiling" ->
                            Just <|
                                S.Apply (S.Select arg "setScale")
                                    [ S.ArgValue Nothing (S.Literal (S.IntegerLit 0))
                                    , S.ArgValue Nothing (S.Ref [ "scala", "math", "BigDecimal", "RoundingMode" ] "CEILING")
                                    ]

                        "truncate" ->
                            Just <|
                                S.Apply (S.Select arg "setScale")
                                    [ S.ArgValue Nothing (S.Literal (S.IntegerLit 0))
                                    , S.ArgValue Nothing (S.Ref [ "scala", "math", "BigDecimal", "RoundingMode" ] "DOWN")
                                    ]

                        "not" ->
                            call "Bool" "not" [ arg ]

                        "negate" ->
                            Just (S.UnOp "-" arg)

                        "abs" ->
                            Just <|
                                S.Apply (S.Ref [ "scala", "math" ] "abs")
                                    [ S.ArgValue Nothing arg
                                    ]

                        "sqrt" ->
                            Just <|
                                S.Apply (S.Ref [ "scala", "math" ] "BigDecimal")
                                    [ S.ArgValue Nothing
                                        (S.Apply (S.Ref [ "scala", "math" ] "sqrt")
                                            [ S.ArgValue Nothing
                                                (S.Select arg "doubleValue")
                                            ]
                                        )
                                    ]

                        "always" ->
                            Just <|
                                S.Lambda [ "_" ] arg

                        _ ->
                            Nothing

                [ left, right ] ->
                    case funName of
                        "add" ->
                            Just (S.BinOp left "+" right)

                        "sub" ->
                            Just (S.BinOp left "-" right)

                        "mul" ->
                            Just (S.BinOp left "*" right)

                        "fdiv" ->
                            Just (S.BinOp left "/" right)

                        "idiv" ->
                            Just (S.BinOp left "/" right)

                        "pow" ->
                            Just <|
                                S.Apply (S.Ref [ "scala", "math" ] "pow")
                                    [ S.ArgValue Nothing left
                                    , S.ArgValue Nothing right
                                    ]

                        "eq" ->
                            Just (S.BinOp left "==" right)

                        "neq" ->
                            Just (S.BinOp left "!=" right)

                        "lt" ->
                            Just (S.BinOp left "<" right)

                        "le" ->
                            Just (S.BinOp left "<=" right)

                        "gt" ->
                            Just (S.BinOp left ">" right)

                        "ge" ->
                            Just (S.BinOp left ">=" right)

                        "min" ->
                            Just <|
                                S.IfElse (S.BinOp left "<" right) left right

                        "max" ->
                            Just <|
                                S.IfElse (S.BinOp left ">" right) left right

                        "and" ->
                            call "Bool" funName [ left, right ]

                        "or" ->
                            call "Bool" funName [ left, right ]

                        "xor" ->
                            call "Bool" funName [ left, right ]

                        "append" ->
                            Just (S.BinOp left "++" right)

                        "composeRight" ->
                            call "Function" funName [ left, right ]

                        "composeLeft" ->
                            call "Function" funName [ left, right ]

                        "pipeRight" ->
                            Just <|
                                S.Apply right
                                    [ S.ArgValue Nothing left
                                    ]

                        "pipeLeft" ->
                            Just <|
                                S.Apply left
                                    [ S.ArgValue Nothing right
                                    ]

                        _ ->
                            Nothing

                [ arg1, arg2, arg3 ] ->
                    case funName of
                        "clamp" ->
                            Just <|
                                S.IfElse (S.BinOp arg3 "<" arg1)
                                    arg1
                                    (S.IfElse (S.BinOp arg3 ">=" arg2)
                                        arg2
                                        arg3
                                    )

                        _ ->
                            Nothing

                _ ->
                    Nothing

        _ ->
            call moduleName funName scalaArgs


mapXToFlatMap : List S.Value -> S.Value -> S.Value
mapXToFlatMap ms f =
    case ( ms, f ) of
        ( [ m ], body ) ->
            S.Apply (S.Select m "map")
                [ S.ArgValue Nothing body
                ]

        ( mh :: mt, S.Lambda [ a ] body ) ->
            S.Apply (S.Select mh "flatMap")
                [ S.ArgValue Nothing
                    (S.Lambda [ a ]
                        (mapXToFlatMap mt body)
                    )
                ]

        ( mh :: mt, body ) ->
            let
                varName =
                    "a" ++ Debug.toString (List.length ms)
            in
            S.Apply (S.Select mh "flatMap")
                [ S.ArgValue Nothing
                    (S.Lambda [ varName ]
                        (mapXToFlatMap mt
                            (S.Apply body
                                [ S.ArgValue Nothing
                                    (S.Var varName)
                                ]
                            )
                        )
                    )
                ]

        ( [], body ) ->
            body


mapConstructor : String -> String -> S.Value
mapConstructor moduleName topCtorName =
    maybeMapConstructor moduleName topCtorName
        |> Maybe.map
            (\( packageName, ctorName ) ->
                S.Ref packageName ctorName
            )
        |> Maybe.withDefault
            (Report.todoValue ("Missing mapping for constructor 'SlateX.Core." ++ moduleName ++ "." ++ topCtorName ++ "'."))


mapMatchConstructor : String -> String -> List S.Pattern -> S.Pattern
mapMatchConstructor moduleName topCtorName args =
    maybeMapConstructor moduleName topCtorName
        |> Maybe.map
            (\( packageName, ctorName ) ->
                S.UnapplyMatch packageName ctorName args
            )
        |> Maybe.withDefault
            (Report.todoPattern ("Missing mapping for constructor 'SlateX.Core." ++ moduleName ++ "." ++ topCtorName ++ "'."))


maybeMapConstructor : String -> String -> Maybe ( S.Path, S.Name )
maybeMapConstructor moduleName ctorName =
    case moduleName of
        "Maybe" ->
            case ctorName of
                "Just" ->
                    Just ( [ "scala" ], "Some" )

                "Nothing" ->
                    Just ( [ "scala" ], "None" )

                _ ->
                    Nothing

        "Result" ->
            case ctorName of
                "Ok" ->
                    Just ( [ "morphir", "sdk", "Result" ], "ok" )

                "Err" ->
                    Just ( [ "morphir", "sdk", "Result" ], "err" )

                _ ->
                    Nothing

        "Rule" ->
            case ctorName of
                "RuleSet" ->
                    Just ( [ "slatex", "core", "rule" ], "RuleSet" )

                _ ->
                    Nothing

        _ ->
            Nothing
