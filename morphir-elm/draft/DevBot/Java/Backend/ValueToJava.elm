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


module SlateX.DevBot.Java.Backend.ValueToJava exposing (applyCoreBinaryToExp, applyCoreUnaryToExp, caseExpToIfElse, escapeString, isEnumValue, isEqual, isUnionValue, literalToExp, pathToPackageName, reportError, reportMissingCoreMapping, valueExpToExp, valueExpToJava, valueExpToLambdaArgsAndBody, valueExpToReturn, valueRefToJavaQName)

import Dict
import Regex
import SlateX.AST.Package.Annotated as AnnotatedPackage
import SlateX.AST.Path exposing (Path)
import SlateX.AST.QName exposing (QName)
import SlateX.AST.Tools.Function as Function
import SlateX.AST.Type as Type
import SlateX.AST.Value as V
import SlateX.AST.Value.Annotated as A
import SlateX.DevBot.Java.Ast as Java
import SlateX.DevBot.Java.Backend.TypeToJava as TypeToJava
import SlateX.Mapping.Naming as Naming


valueExpToReturn : AnnotatedPackage.Package Type.Exp -> Path -> A.Exp Type.Exp -> List Java.Exp
valueExpToReturn lib currentModulePath value =
    case valueExpToExp lib currentModulePath value of
        (Java.IfElse _ _ _) as bodyExp ->
            [ bodyExp ]

        (Java.Throw _) as bodyExp ->
            [ bodyExp ]

        Java.Statements exps ->
            let
                returnLast es =
                    case es of
                        [] ->
                            []

                        [ lastExp ] ->
                            [ Java.Return lastExp ]

                        firstExp :: restOfExps ->
                            firstExp :: returnLast restOfExps
            in
            returnLast exps

        bodyExp ->
            [ Java.Return bodyExp ]


valueExpToExp : AnnotatedPackage.Package Type.Exp -> Path -> A.Exp Type.Exp -> Java.Exp
valueExpToExp lib currentModulePath value =
    valueExpToJava lib currentModulePath value Nothing


valueExpToJava : AnnotatedPackage.Package Type.Exp -> Path -> A.Exp Type.Exp -> Maybe Java.Type -> Java.Exp
valueExpToJava lib currentModulePath value maybeExpectedType =
    let
        flattenApply exp =
            case exp of
                A.Apply fun arg _ ->
                    case flattenApply fun of
                        ( e, args ) ->
                            ( e, args ++ [ arg ] )

                _ ->
                    ( exp, [] )
    in
    case value of
        A.Literal lit _ ->
            literalToExp lit

        A.Variable name _ ->
            Java.Variable (Naming.toCamelCase name)

        A.Reference ref _ ->
            case maybeExpectedType of
                Just (Java.Predicate _) ->
                    Java.Lambda [ "a" ] <|
                        Java.Apply
                            (Java.ValueRef <| valueRefToJavaQName lib ref)
                            [ Java.Variable "a" ]

                Just (Java.Function _ _) ->
                    Java.Lambda [ "a" ] <|
                        Java.Apply
                            (Java.ValueRef <| valueRefToJavaQName lib ref)
                            [ Java.Variable "a" ]

                _ ->
                    Java.ValueRef <| valueRefToJavaQName lib ref

        A.FieldAccess exp name tpe ->
            case tpe of
                Type.Function _ _ ->
                    Java.Select (valueExpToExp lib currentModulePath exp) (Naming.toCamelCase name)

                _ ->
                    Java.Apply (Java.Select (valueExpToExp lib currentModulePath exp) ("get" ++ Naming.toTitleCase name)) []

        A.FieldAccessFunction name tpe ->
            case tpe of
                Type.Function _ (Type.Function _ _) ->
                    Java.Lambda [ "a" ]
                        (Java.Select (Java.Variable "a") (Naming.toCamelCase name))

                _ ->
                    Java.Lambda [ "a" ]
                        (Java.Apply (Java.Select (Java.Variable "a") ("get" ++ Naming.toTitleCase name)) [])

        A.Constructor ( modulePath, typeName ) _ ->
            case modulePath of
                [ [ "maybe" ] ] ->
                    case typeName of
                        [ "just" ] ->
                            Java.ValueRef [ "java", "util", "Optional", "of" ]

                        [ "nothing" ] ->
                            Java.Apply
                                (Java.ValueRef [ "java", "util", "Optional", "empty" ])
                                []

                        other ->
                            reportError ("Unknown Maybe function: " ++ Debug.toString other)

                _ ->
                    if isEnumValue lib ( modulePath, typeName ) then
                        Java.ValueRef (TypeToJava.typeRefToJavaQName lib currentModulePath ( modulePath, typeName ))

                    else if isUnionValue lib ( modulePath, typeName ) then
                        Java.ConstructorRef (TypeToJava.typeRefToJavaQName lib currentModulePath ( modulePath, typeName ))

                    else
                        Java.ConstructorRef (TypeToJava.typeRefToJavaQName lib currentModulePath ( modulePath, typeName ++ [ "value" ] ))

        A.Apply (A.Apply (A.Reference ( [ [ "slate", "x" ], [ "core" ], moduleName ], functionName ) _) arg1 _) arg2 _ ->
            applyCoreBinaryToExp
                (valueExpToJava lib currentModulePath)
                (moduleName |> Naming.toTitleCase)
                (functionName |> Naming.toCamelCase)
                arg1
                arg2

        A.Apply (A.Reference ( [ [ "slate", "x" ], [ "core" ], moduleName ], functionName ) _) arg _ ->
            applyCoreUnaryToExp
                (valueExpToJava lib currentModulePath)
                (moduleName |> Naming.toTitleCase)
                (functionName |> Naming.toCamelCase)
                arg

        A.Apply fun arg _ ->
            let
                isVariableAtBottom exp =
                    case exp of
                        A.Variable _ _ ->
                            True

                        A.Apply f _ _ ->
                            isVariableAtBottom f

                        _ ->
                            False

                toApply exp =
                    case exp of
                        A.Apply f a _ ->
                            Java.Apply
                                (Java.Select (toApply f) "apply")
                                [ valueExpToExp lib currentModulePath a ]

                        _ ->
                            valueExpToExp lib currentModulePath exp
            in
            if isVariableAtBottom value then
                toApply value

            else
                let
                    ( f, args ) =
                        flattenApply value
                in
                case f of
                    -- If this is a reference to a function let's make sure all arguments are applied
                    A.Reference ( modulePath, localName ) _ ->
                        lib.implementation
                            |> Dict.get modulePath
                            |> Maybe.map .valueTypes
                            |> Maybe.andThen (Dict.get localName)
                            |> Maybe.map
                                (\funType ->
                                    let
                                        argTypes =
                                            Function.argTypes funType

                                        extraLambdaArgs =
                                            List.range (List.length args + 1) (List.length argTypes)
                                                |> List.map
                                                    (\index ->
                                                        "arg" ++ Debug.toString index
                                                    )

                                        extraArgs =
                                            List.range (List.length args + 1) (List.length argTypes)
                                                |> List.map
                                                    (\index ->
                                                        Java.Variable ("arg" ++ Debug.toString index)
                                                    )

                                        allArgs =
                                            (args |> List.map (valueExpToExp lib currentModulePath)) ++ extraArgs
                                    in
                                    if List.isEmpty extraArgs then
                                        Java.Apply (valueExpToExp lib currentModulePath f) allArgs

                                    else
                                        Java.Lambda extraLambdaArgs
                                            (Java.Apply (valueExpToExp lib currentModulePath f) allArgs)
                                )
                            |> Maybe.withDefault
                                (Java.Apply (valueExpToExp lib currentModulePath f)
                                    (args
                                        |> List.map (valueExpToExp lib currentModulePath)
                                    )
                                )

                    _ ->
                        Java.Apply (valueExpToExp lib currentModulePath f)
                            (args
                                |> List.map (valueExpToExp lib currentModulePath)
                            )

        A.Lambda argPattern bodyExp _ ->
            case argPattern of
                A.MatchAny _ ->
                    Java.Lambda [ "a" ]
                        (valueExpToExp lib currentModulePath bodyExp)

                A.MatchAnyAlias argName _ ->
                    Java.Lambda [ argName |> Naming.toCamelCase ]
                        (valueExpToExp lib currentModulePath bodyExp)

                _ ->
                    reportError ("Only alias patterns are supported in lambda args. Found this instead: " ++ escapeString (Debug.toString argPattern))

        (A.LetExp _ _ _ _) as letExp ->
            let
                flattenLet exp =
                    case exp of
                        A.LetExp bindPattern bindExp ie _ ->
                            case flattenLet ie of
                                ( restOfBindings, finalInExp ) ->
                                    ( ( bindPattern, bindExp ) :: restOfBindings, finalInExp )

                        _ ->
                            ( [], exp )

                ( bindings, inExp ) =
                    flattenLet letExp

                javaBindings =
                    bindings
                        |> List.filterMap
                            (\( pattern, exp ) ->
                                case pattern of
                                    A.MatchAnyAlias name tpe ->
                                        Just
                                            (Java.VariableDecl
                                                [ Java.Final ]
                                                (tpe |> TypeToJava.typeExpToType lib currentModulePath)
                                                (name |> Naming.toCamelCase)
                                                (exp |> valueExpToExp lib currentModulePath |> Just)
                                            )

                                    _ ->
                                        Nothing
                            )

                javaInExp =
                    valueExpToExp lib currentModulePath inExp
            in
            Java.Statements
                (javaBindings ++ [ javaInExp ])

        A.IfExp cond whenTrue whenFalse _ ->
            Java.Ternary
                (valueExpToExp lib currentModulePath cond)
                (valueExpToExp lib currentModulePath whenTrue)
                (valueExpToExp lib currentModulePath whenFalse)

        A.CaseExp ofExp cases tpe ->
            {- if A.annotation ofExp |> isEnumType then
                   Java.Switch
                       (valueExpToExp lib currentModulePath ofExp)
                       ()
                       Nothing
               else
            -}
            caseExpToIfElse lib currentModulePath ofExp cases tpe

        A.List itemExps _ ->
            Java.Apply (Java.ValueRef [ "java", "util", "stream", "Stream", "of" ])
                (itemExps
                    |> List.map (valueExpToExp lib currentModulePath)
                )

        A.Record fields (Type.Constructor ( modulePath, typeName ) _) ->
            Java.Apply
                (Java.ConstructorRef (TypeToJava.typeRefToJavaQName lib currentModulePath ( modulePath, typeName ++ [ "value" ] )))
                (fields
                    |> List.map
                        (\( fieldName, fieldValue ) ->
                            fieldValue |> valueExpToExp lib currentModulePath
                        )
                )

        exp ->
            reportError (Debug.toString exp)


literalToExp : V.Lit -> Java.Exp
literalToExp lit =
    case lit of
        V.BooleanLit bool ->
            Java.BooleanLit bool

        V.StringLit string ->
            Java.StringLit string

        V.IntegerLit int ->
            Java.Apply
                (Java.ConstructorRef [ "java", "math", "BigInteger" ])
                [ Java.StringLit (Debug.toString int)
                ]

        V.FloatLit float ->
            if float == 0.0 then
                Java.ValueRef [ "java", "math", "BigDecimal", "ZERO" ]

            else
                Java.Apply
                    (Java.ConstructorRef [ "java", "math", "BigDecimal" ])
                    [ Java.StringLit (Debug.toString float)
                    ]

        _ ->
            Debug.todo "Not handled"


applyCoreUnaryToExp : (A.Exp Type.Exp -> Maybe Java.Type -> Java.Exp) -> String -> String -> A.Exp Type.Exp -> Java.Exp
applyCoreUnaryToExp expToJava moduleName functionName arg =
    case moduleName of
        "Annotation" ->
            case functionName of
                "native" ->
                    Java.Throw
                        (Java.Apply
                            (Java.ConstructorRef [ "java", "lang", "UnsupportedOperationException" ])
                            [ Java.StringLit "This is a native function that is not implemented yet." ]
                        )

                _ ->
                    reportMissingCoreMapping moduleName functionName

        "Basics" ->
            case functionName of
                "not" ->
                    Java.UnaryOp "!" (expToJava arg Nothing)

                "abs" ->
                    Java.Apply (Java.Select (expToJava arg Nothing) "abs") []

                "toDecimal" ->
                    Java.Apply
                        (Java.ConstructorRef [ "java", "math", "BigDecimal" ])
                        [ expToJava arg Nothing ]

                _ ->
                    reportMissingCoreMapping moduleName functionName

        "List" ->
            case functionName of
                "sum" ->
                    Java.Apply (Java.Select (expToJava arg Nothing) "reduce")
                        [ Java.ValueRef [ "java", "math", "BigDecimal", "ZERO" ]
                        , Java.Lambda [ "a", "b" ]
                            (Java.Apply (Java.Select (Java.Variable "a") "add") [ Java.Variable "b" ])
                        ]

                "concat" ->
                    Java.Apply (Java.Select (expToJava arg Nothing) "reduce")
                        [ Java.Apply (Java.ValueRef [ "java", "util", "stream", "Stream", "of" ]) []
                        , Java.Lambda [ "a", "b" ]
                            (Java.Apply (Java.ValueRef [ "java", "util", "stream", "Stream", "concat" ])
                                [ Java.Variable "a"
                                , Java.Variable "b"
                                ]
                            )
                        ]

                "head" ->
                    Java.Apply (Java.Select (expToJava arg Nothing) "findFirst") []

                _ ->
                    reportMissingCoreMapping moduleName functionName

        "String" ->
            case functionName of
                "length" ->
                    Java.Apply (Java.Select (expToJava arg Nothing) "length") []

                "trim" ->
                    Java.Apply (Java.Select (expToJava arg Nothing) "trim") []

                "toUpper" ->
                    Java.Apply (Java.Select (expToJava arg Nothing) "toUpperCase") []

                "toLower" ->
                    Java.Apply (Java.Select (expToJava arg Nothing) "toLowerCase") []

                _ ->
                    reportMissingCoreMapping moduleName functionName

        "Tuple" ->
            case functionName of
                "first" ->
                    Java.Apply (Java.Select (expToJava arg Nothing) "getKey") []

                "second" ->
                    Java.Apply (Java.Select (expToJava arg Nothing) "getValue") []

                _ ->
                    reportMissingCoreMapping moduleName functionName

        _ ->
            reportMissingCoreMapping moduleName functionName


applyCoreBinaryToExp : (A.Exp Type.Exp -> Maybe Java.Type -> Java.Exp) -> String -> String -> A.Exp Type.Exp -> A.Exp Type.Exp -> Java.Exp
applyCoreBinaryToExp expToJava moduleName functionName arg1 arg2 =
    case moduleName of
        "Basics" ->
            case functionName of
                "eq" ->
                    Java.Apply (Java.Select (expToJava arg1 Nothing) "equals") [ expToJava arg2 Nothing ]

                "neq" ->
                    Java.UnaryOp "!" (Java.Apply (Java.Select (expToJava arg1 Nothing) "equals") [ expToJava arg2 Nothing ])

                "and" ->
                    Java.BinOp (expToJava arg1 Nothing) "&&" (expToJava arg2 Nothing)

                "or" ->
                    Java.BinOp (expToJava arg1 Nothing) "||" (expToJava arg2 Nothing)

                "lt" ->
                    Java.BinOp (Java.Apply (Java.Select (expToJava arg1 Nothing) "compareTo") [ expToJava arg2 Nothing ]) "<" (Java.IntLit 0)

                "le" ->
                    Java.BinOp (Java.Apply (Java.Select (expToJava arg1 Nothing) "compareTo") [ expToJava arg2 Nothing ]) "<=" (Java.IntLit 0)

                "gt" ->
                    Java.BinOp (Java.Apply (Java.Select (expToJava arg1 Nothing) "compareTo") [ expToJava arg2 Nothing ]) ">" (Java.IntLit 0)

                "ge" ->
                    Java.BinOp (Java.Apply (Java.Select (expToJava arg1 Nothing) "compareTo") [ expToJava arg2 Nothing ]) ">=" (Java.IntLit 0)

                "min" ->
                    Java.Apply (Java.Select (expToJava arg1 Nothing) "min") [ expToJava arg2 Nothing ]

                "max" ->
                    Java.Apply (Java.Select (expToJava arg1 Nothing) "max") [ expToJava arg2 Nothing ]

                "add" ->
                    Java.Apply (Java.Select (expToJava arg1 Nothing) "add") [ expToJava arg2 Nothing ]

                "sub" ->
                    Java.Apply (Java.Select (expToJava arg1 Nothing) "subtract") [ expToJava arg2 Nothing ]

                "mul" ->
                    Java.Apply (Java.Select (expToJava arg1 Nothing) "multiply") [ expToJava arg2 Nothing ]

                "fdiv" ->
                    Java.Apply
                        (Java.ConstructorRef [ "java", "math", "BigDecimal" ])
                        [ Java.BinOp (Java.Apply (Java.Select (expToJava arg1 Nothing) "doubleValue") []) "/" (Java.Apply (Java.Select (expToJava arg2 Nothing) "doubleValue") []) ]

                _ ->
                    reportMissingCoreMapping moduleName functionName

        "String" ->
            case functionName of
                "contains" ->
                    Java.Apply (Java.Select (expToJava arg1 Nothing) "contains") [ expToJava arg2 Nothing ]

                _ ->
                    reportMissingCoreMapping moduleName functionName

        "Maybe" ->
            case functionName of
                "map" ->
                    Java.Apply (Java.Select (expToJava arg2 Nothing) "map") [ expToJava arg1 Nothing ]

                "withDefault" ->
                    Java.Apply (Java.Select (expToJava arg2 Nothing) "orElse") [ expToJava arg1 Nothing ]

                _ ->
                    reportMissingCoreMapping moduleName functionName

        "List" ->
            case functionName of
                "map" ->
                    Java.Apply (Java.Select (expToJava arg2 Nothing) "map") [ expToJava arg1 Nothing ]

                "filter" ->
                    Java.Apply (Java.Select (expToJava arg2 Nothing) "filter")
                        [ expToJava arg1 <| Just <| Java.Predicate <| Java.TypeVar "a" -- TODO: use the actual type instead of the type variable
                        ]

                "member" ->
                    Java.Apply (Java.Select (expToJava arg2 Nothing) "anyMatch")
                        [ Java.Lambda [ "a" ]
                            (isEqual (arg1 |> A.annotation) (Java.Variable "a") (expToJava arg1 Nothing))
                        ]

                _ ->
                    reportMissingCoreMapping moduleName functionName

        "LocalDate" ->
            case functionName of
                "min" ->
                    Java.Ternary
                        (Java.Apply (Java.Select (expToJava arg1 Nothing) "isBefore") [ expToJava arg2 Nothing ])
                        (expToJava arg1 Nothing)
                        (expToJava arg2 Nothing)

                "max" ->
                    Java.Ternary
                        (Java.Apply (Java.Select (expToJava arg1 Nothing) "isAfter") [ expToJava arg2 Nothing ])
                        (expToJava arg1 Nothing)
                        (expToJava arg2 Nothing)

                "plusDays" ->
                    Java.Apply (Java.Select (expToJava arg2 Nothing) "plusDays")
                        [ Java.Apply (Java.Select (expToJava arg1 Nothing) "longValue") []
                        ]

                "diffInDays" ->
                    Java.Apply (Java.ValueRef [ "java", "math", "BigInteger", "valueOf" ])
                        [ Java.Apply
                            (Java.Select
                                (Java.Apply (Java.ValueRef [ "java", "time", "Period", "between" ])
                                    [ expToJava arg1 Nothing
                                    , expToJava arg2 Nothing
                                    ]
                                )
                                "getDays"
                            )
                            []
                        ]

                _ ->
                    reportMissingCoreMapping moduleName functionName

        _ ->
            reportMissingCoreMapping moduleName functionName


reportMissingCoreMapping : String -> String -> Java.Exp
reportMissingCoreMapping moduleName functionName =
    Java.Throw
        (Java.Apply
            (Java.ConstructorRef [ "java", "lang", "UnsupportedOperationException" ])
            [ Java.StringLit ("Missing mapping for function: SlateX.Core." ++ moduleName ++ "." ++ functionName) ]
        )


caseExpToIfElse : AnnotatedPackage.Package Type.Exp -> Path -> A.Exp Type.Exp -> List ( A.Pattern Type.Exp, A.Exp Type.Exp ) -> Type.Exp -> Java.Exp
caseExpToIfElse lib currentModulePath ofExp cases tpe =
    let
        casesToExp oe cs shouldReturn =
            case cs of
                [] ->
                    Java.Throw
                        (Java.Apply
                            (Java.ConstructorRef [ "java", "lang", "IllegalArgumentException" ])
                            [ Java.BinOp (Java.StringLit "Unexpected value: ") "+" oe ]
                        )

                ( firstCasePattern, firstCaseExp ) :: restOfCases ->
                    case firstCasePattern of
                        A.MatchConstructor ref [] _ ->
                            Java.IfElse
                                (Java.Apply (Java.Select oe "equals")
                                    [ Java.ValueRef (TypeToJava.typeRefToJavaQName lib currentModulePath ref)
                                    ]
                                )
                                (valueExpToReturn lib currentModulePath firstCaseExp)
                                [ casesToExp oe restOfCases shouldReturn ]

                        A.MatchAny _ ->
                            if shouldReturn then
                                Java.Statements (valueExpToReturn lib currentModulePath firstCaseExp)

                            else
                                valueExpToExp lib currentModulePath firstCaseExp

                        A.MatchLiteral lit _ ->
                            Java.Ternary
                                (Java.Apply (Java.Select oe "equals")
                                    [ literalToExp lit ]
                                )
                                (valueExpToExp lib currentModulePath firstCaseExp)
                                (casesToExp oe restOfCases False)

                        pattern ->
                            reportError (Debug.toString pattern)
    in
    casesToExp (valueExpToExp lib currentModulePath ofExp) cases True


valueExpToLambdaArgsAndBody : AnnotatedPackage.Package Type.Exp -> Path -> List String -> A.Exp Type.Exp -> ( List String, Java.Exp )
valueExpToLambdaArgsAndBody lib currentModulePath argNames value =
    case ( argNames, value ) of
        ( [ singleArgName ], A.Lambda (A.MatchAnyAlias argName _) body _ ) ->
            ( [ Naming.toCamelCase argName ], valueExpToExp lib currentModulePath body )

        ( [ singleArgName ], body ) ->
            let
                javaBody =
                    case valueExpToExp lib currentModulePath value of
                        Java.Apply exp args ->
                            Java.Apply exp (args ++ [ Java.Variable singleArgName ])

                        other ->
                            Java.Apply other [ Java.Variable singleArgName ]
            in
            ( [ singleArgName ], javaBody )

        _ ->
            Debug.todo "TODO"


valueRefToJavaQName : AnnotatedPackage.Package Type.Exp -> QName -> Java.QualifiedIdentifier
valueRefToJavaQName lib ref =
    case ref of
        ( modulePath, localName ) ->
            case ( List.reverse modulePath, localName ) of
                ( moduleName :: modulePathReversed, _ ) ->
                    pathToPackageName (List.reverse modulePathReversed) ++ [ Naming.toTitleCase moduleName, Naming.toCamelCase localName ]

                _ ->
                    Debug.todo "TODO"


isEnumValue : AnnotatedPackage.Package Type.Exp -> QName -> Bool
isEnumValue package ( modulePath, typeName ) =
    package.implementation
        |> Dict.get modulePath
        |> Maybe.map
            (\moduleImpl ->
                moduleImpl.unionTypes
                    |> Dict.toList
                    |> List.filter
                        (\( _, union ) ->
                            union.cases
                                |> List.filter
                                    (\( name, args ) ->
                                        name
                                            == typeName
                                            && List.isEmpty args
                                    )
                                |> List.isEmpty
                                |> Basics.not
                        )
                    |> List.isEmpty
                    |> Basics.not
            )
        |> Maybe.withDefault False


isUnionValue : AnnotatedPackage.Package Type.Exp -> QName -> Bool
isUnionValue package ( modulePath, typeName ) =
    package.implementation
        |> Dict.get modulePath
        |> Maybe.map
            (\moduleImpl ->
                moduleImpl.unionTypes
                    |> Dict.toList
                    |> List.filter
                        (\( _, union ) ->
                            union.cases
                                |> List.filter
                                    (\( name, args ) ->
                                        name == typeName
                                    )
                                |> List.isEmpty
                                |> Basics.not
                        )
                    |> List.isEmpty
                    |> Basics.not
            )
        |> Maybe.withDefault False


pathToPackageName : Path -> Java.QualifiedIdentifier
pathToPackageName path =
    path |> List.map (String.join "")


escapeString : String -> String
escapeString string =
    string
        |> Regex.replace (Regex.fromString "\\\"" |> Maybe.withDefault Regex.never)
            (\match -> "'")


reportError : String -> Java.Exp
reportError msg =
    Java.Throw
        (Java.Apply
            (Java.ConstructorRef [ "java", "lang", "UnsupportedOperationException" ])
            [ Java.StringLit ("Error during code generation: " ++ escapeString msg) ]
        )


isEqual : Type.Exp -> Java.Exp -> Java.Exp -> Java.Exp
isEqual tpe a b =
    if TypeToJava.isPrimitive tpe then
        Java.BinOp a "==" b

    else
        Java.Apply (Java.Select a "equals") [ b ]
