module Morphir.Elm.FrontendTests exposing (..)

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

import Dict exposing (Dict)
import Expect exposing (Expectation)
import Json.Encode as Encode
import Morphir.Elm.Frontend as Frontend exposing (ContentRange, Errors, SourceFile, SourceLocation, parseRawValue)
import Morphir.Elm.Frontend.Codec as FrontendCodec
import Morphir.IR.AccessControlled exposing (AccessControlled, public)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName exposing (fQName, fqn)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Basics as SDKBasics
import Morphir.IR.SDK.Decimal as Decimal
import Morphir.IR.SDK.Int as SDKInt
import Morphir.IR.SDK.List as List
import Morphir.IR.SDK.Maybe as Maybe
import Morphir.IR.SDK.Rule as Rule
import Morphir.IR.SDK.String as String
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value exposing (Definition, Pattern(..), RawValue, Value(..))
import Set exposing (Set)
import Test exposing (..)


opts : Frontend.Options
opts =
    { typesOnly = False
    }


parseRawValueTests : Test
parseRawValueTests =
    let
        positiveTest : String -> RawValue -> Test
        positiveTest input expectedResult =
            test input
                (\_ ->
                    parseRawValue (Library [ [ "empty" ] ] Dict.empty Package.emptyDefinition) input
                        |> Expect.equal (Ok expectedResult)
                )
    in
    describe "parseRawValue"
        [ positiveTest "1 + 2"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "Basics" "add"))
                    (Value.Literal () (WholeNumberLiteral 1))
                )
                (Value.Literal () (WholeNumberLiteral 2))
            )
        , positiveTest "List.filter ((+) 1) []"
            (Value.Apply ()
                (Value.Apply ()
                    (Value.Reference () (fqn "Morphir.SDK" "List" "filter"))
                    (Value.Apply ()
                        (Value.Reference () (fqn "Morphir.SDK" "Basics" "add"))
                        (Value.Literal () (WholeNumberLiteral 1))
                    )
                )
                (Value.List () [])
            )
        ]


frontendTest : Test
frontendTest =
    let
        sourceA =
            { path = "My/Package/A.elm"
            , content =
                String.join "\n"
                    [ "module My.Package.A exposing (..)"
                    , ""
                    , "import My.Package.B exposing (Bee)"
                    , ""
                    , "import Morphir.SDK.Rule exposing (Rule)"
                    , ""
                    , "import Morphir.SDK.Decimal exposing (Decimal)"
                    , ""
                    , "import Morphir.SDK.Int exposing (Int8, Int16, Int32, Int64)"
                    , ""
                    , "type Foo = Foo Bee"
                    , ""
                    , "type alias Bar = Foo"
                    , ""
                    , "{-| It's a rec -}"
                    , "type alias Rec ="
                    , "    { field1 : Foo"
                    , "    , field2 : Bar"
                    , "    , field3 : Bool"
                    , "    , field4 : Int"
                    , "    , field5 : Float"
                    , "    , field6 : String"
                    , "    , field7 : Maybe Int"
                    , "    , field8 : List Float"
                    , "    , field9 : Rule Int Int"
                    , "    , field10 : Decimal"
                    , "    , field11 : Int8"
                    , "    , field12 : Int16"
                    , "    , field13 : Int32"
                    , "    , field14 : Int64"
                    , "    }"
                    ]
            }

        sourceB =
            { path = "My/Package/B.elm"
            , content =
                String.join "\n"
                    [ "module My.Package.B exposing (..)"
                    , ""
                    , "{-| It's a bee -}"
                    , "type Bee = Bee"
                    ]
            }

        sourceC =
            { path = "My/Package/C.elm"
            , content =
                String.join "\n"
                    [ "module My.Package.C exposing (..)"
                    , ""
                    , "type Cee = Cee"
                    ]
            }

        packageName =
            Path.fromString "My.Package"

        moduleA =
            Path.fromString "A"

        moduleB =
            Path.fromString "B"

        packageInfo =
            { name =
                packageName
            , exposedModules =
                Just
                    (Set.fromList
                        [ moduleA
                        , moduleB
                        ]
                    )
            }

        expected : Package.Definition () ()
        expected =
            { modules =
                Dict.fromList
                    [ ( moduleA
                      , public
                            { types =
                                Dict.fromList
                                    [ ( [ "bar" ]
                                      , public
                                            (Documented ""
                                                (Type.TypeAliasDefinition []
                                                    (Type.Reference () (fQName packageName [ [ "a" ] ] [ "foo" ]) [])
                                                )
                                            )
                                      )
                                    , ( [ "foo" ]
                                      , public
                                            (Documented ""
                                                (Type.CustomTypeDefinition []
                                                    (public
                                                        (Dict.fromList
                                                            [ ( [ "foo" ]
                                                              , [ ( [ "arg", "1" ], Type.Reference () (fQName packageName [ [ "b" ] ] [ "bee" ]) [] )
                                                                ]
                                                              )
                                                            ]
                                                        )
                                                    )
                                                )
                                            )
                                      )
                                    , ( [ "rec" ]
                                      , public
                                            (Documented " It's a rec "
                                                (Type.TypeAliasDefinition []
                                                    (Type.Record ()
                                                        [ Type.Field [ "field", "1" ]
                                                            (Type.Reference () (fQName packageName [ [ "a" ] ] [ "foo" ]) [])
                                                        , Type.Field [ "field", "2" ]
                                                            (Type.Reference () (fQName packageName [ [ "a" ] ] [ "bar" ]) [])
                                                        , Type.Field [ "field", "3" ]
                                                            (SDKBasics.boolType ())
                                                        , Type.Field [ "field", "4" ]
                                                            (SDKBasics.intType ())
                                                        , Type.Field [ "field", "5" ]
                                                            (SDKBasics.floatType ())
                                                        , Type.Field [ "field", "6" ]
                                                            (String.stringType ())
                                                        , Type.Field [ "field", "7" ]
                                                            (Maybe.maybeType () (SDKBasics.intType ()))
                                                        , Type.Field [ "field", "8" ]
                                                            (List.listType () (SDKBasics.floatType ()))
                                                        , Type.Field [ "field", "9" ]
                                                            (Rule.ruleType () (SDKBasics.intType ()) (SDKBasics.intType ()))
                                                        , Type.Field [ "field", "10" ]
                                                            (Decimal.decimalType ())
                                                        , Type.Field [ "field", "11" ]
                                                            (SDKInt.int8Type ())
                                                        , Type.Field [ "field", "12" ]
                                                            (SDKInt.int16Type ())
                                                        , Type.Field [ "field", "13" ]
                                                            (SDKInt.int32Type ())
                                                        , Type.Field [ "field", "14" ]
                                                            (SDKInt.int64Type ())
                                                        ]
                                                    )
                                                )
                                            )
                                      )
                                    ]
                            , values =
                                Dict.empty
                            , doc = Nothing
                            }
                      )
                    , ( moduleB
                      , public
                            { types =
                                Dict.fromList
                                    [ ( [ "bee" ]
                                      , public
                                            (Documented " It's a bee "
                                                (Type.CustomTypeDefinition []
                                                    (public (Dict.fromList [ ( [ "bee" ], [] ) ]))
                                                )
                                            )
                                      )
                                    ]
                            , values =
                                Dict.empty
                            , doc = Nothing
                            }
                      )
                    ]
            }
    in
    test "first" <|
        \_ ->
            Frontend.packageDefinitionFromSource opts packageInfo Dict.empty [ sourceA, sourceB, sourceC ]
                |> Result.map Package.eraseDefinitionAttributes
                |> Expect.equal (Ok expected)


valueTests : Test
valueTests =
    let
        packageInfo =
            { name = [ [ "my" ] ]
            , exposedModules =
                Just (Set.fromList [ [ [ "test" ] ] ])
            }

        otherPackage : Package.Specification ()
        otherPackage =
            Package.Specification
                (Dict.fromList
                    [ ( [ [ "bar" ] ]
                      , { types =
                            Dict.empty
                        , values =
                            Dict.empty
                        , doc = Nothing
                        }
                      )
                    ]
                )

        deps : Dict Path (Package.Specification ())
        deps =
            Dict.fromList
                [ ( [ [ "my", "pack" ] ]
                  , otherPackage
                  )
                ]

        barSource : SourceFile
        barSource =
            { path = "Bar.elm"
            , content =
                String.join "\n"
                    [ "module My.Bar exposing (..)"
                    , ""
                    , "type Baz = Baz"
                    , ""
                    , "foo : Int"
                    , "foo = 1"
                    ]
            }

        moduleSource : String -> SourceFile
        moduleSource sourceValue =
            { path = "Test.elm"
            , content =
                String.join "\n"
                    [ "module My.Test exposing (..)"
                    , ""
                    , "import My.Bar as Bar"
                    , "import MyPack.Bar"
                    , ""
                    , "type Foo = Foo"
                    , ""
                    , "foo : Int"
                    , "foo = 0"
                    , ""
                    , "bar : Int"
                    , "bar = 0"
                    , ""
                    , "baz : Int"
                    , "baz = 0"
                    , ""
                    , "a : Int"
                    , "a = 1"
                    , ""
                    , "b : Int"
                    , "b = 2"
                    , ""
                    , "c : Int"
                    , "c = 3"
                    , ""
                    , "d : Int"
                    , "d = 4"
                    , ""
                    , "e : Int"
                    , "e = 4"
                    , ""
                    , "f : Int"
                    , "f = 5"
                    , ""
                    , "testValue : a"
                    , "testValue = " ++ sourceValue
                    ]
            }

        checkIR : String -> Value () () -> Test
        checkIR valueSource expectedValueIR =
            test valueSource <|
                \_ ->
                    Frontend.packageDefinitionFromSource opts packageInfo deps [ barSource, moduleSource valueSource ]
                        |> Result.map Package.eraseDefinitionAttributes
                        |> Result.mapError
                            (\errors ->
                                Encode.encode 0 (Encode.list FrontendCodec.encodeError errors)
                            )
                        |> Result.andThen
                            (\packageDef ->
                                packageDef.modules
                                    |> Dict.get [ [ "test" ] ]
                                    |> Result.fromMaybe "Could not find test module"
                                    |> Result.andThen
                                        (\moduleDef ->
                                            moduleDef.value.values
                                                |> Dict.get [ "test", "value" ]
                                                |> Result.fromMaybe "Could not find test value"
                                                |> Result.map (.value >> .value >> .body)
                                        )
                            )
                        |> resultToExpectation expectedValueIR

        ref : String -> Value () ()
        ref name =
            Reference () (fQName [ [ "my" ] ] [ [ "test" ] ] [ name ])

        var : String -> Value () ()
        var name =
            Variable () [ name ]

        pvar : String -> Pattern ()
        pvar name =
            AsPattern () (WildcardPattern ()) (Name.fromString name)

        binary : (() -> Value () ()) -> Value () () -> Value () () -> Value () ()
        binary fun arg1 arg2 =
            Apply () (Apply () (fun ()) arg1) arg2
    in
    describe "Values are mapped correctly"
        [ checkIR "()" <| Unit ()
        , checkIR "1" <| Literal () (WholeNumberLiteral 1)
        , checkIR "0x20" <| Literal () (WholeNumberLiteral 32)
        , checkIR "1.5" <| Literal () (FloatLiteral 1.5)
        , checkIR "\"foo\"" <| Literal () (StringLiteral "foo")
        , checkIR "True" <| Literal () (BoolLiteral True)
        , checkIR "False" <| Literal () (BoolLiteral False)
        , checkIR "'A'" <| Literal () (CharLiteral 'A')
        , checkIR "foo" <| ref "foo"
        , checkIR "Bar.foo" <| Reference () (fQName [ [ "my" ] ] [ [ "bar" ] ] [ "foo" ])

        --, checkIR "MyPack.Bar.foo" <| Reference () (fQName [] [ [ "my", "pack" ], [ "bar" ] ] [ "foo" ])
        , checkIR "foo bar" <| Apply () (ref "foo") (ref "bar")
        , checkIR "foo bar baz" <| Apply () (Apply () (ref "foo") (ref "bar")) (ref "baz")
        , checkIR "-1" <| SDKBasics.negate () () (Literal () (WholeNumberLiteral 1))
        , checkIR "if foo then bar else baz" <| IfThenElse () (ref "foo") (ref "bar") (ref "baz")
        , checkIR "( foo, bar, baz )" <| Tuple () [ ref "foo", ref "bar", ref "baz" ]
        , checkIR "( foo )" <| ref "foo"
        , checkIR "[ foo, bar, baz ]" <| List () [ ref "foo", ref "bar", ref "baz" ]
        , checkIR "{ foo = foo, bar = bar, baz = baz }" <| Record () <| Dict.fromList [ ( [ "foo" ], ref "foo" ), ( [ "bar" ], ref "bar" ), ( [ "baz" ], ref "baz" ) ]
        , checkIR "foo.bar" <| Field () (ref "foo") [ "bar" ]
        , checkIR ".bar" <| FieldFunction () [ "bar" ]
        , checkIR "{ a | foo = foo, bar = bar }" <| UpdateRecord () (Variable () [ "a" ]) <| Dict.fromList [ ( [ "foo" ], ref "foo" ), ( [ "bar" ], ref "bar" ) ]
        , checkIR "\\() -> foo " <| Lambda () (UnitPattern ()) (ref "foo")
        , checkIR "\\() () -> foo " <| Lambda () (UnitPattern ()) (Lambda () (UnitPattern ()) (ref "foo"))
        , checkIR "\\_ -> foo " <| Lambda () (WildcardPattern ()) (ref "foo")
        , checkIR "\\'a' -> foo " <| Lambda () (LiteralPattern () (CharLiteral 'a')) (ref "foo")
        , checkIR "\\\"foo\" -> foo " <| Lambda () (LiteralPattern () (StringLiteral "foo")) (ref "foo")
        , checkIR "\\42 -> foo " <| Lambda () (LiteralPattern () (WholeNumberLiteral 42)) (ref "foo")
        , checkIR "\\0x20 -> foo " <| Lambda () (LiteralPattern () (WholeNumberLiteral 32)) (ref "foo")
        , checkIR "\\( 1, 2 ) -> foo " <| Lambda () (TuplePattern () [ LiteralPattern () (WholeNumberLiteral 1), LiteralPattern () (WholeNumberLiteral 2) ]) (ref "foo")
        , checkIR "\\1 :: 2 -> foo " <| Lambda () (HeadTailPattern () (LiteralPattern () (WholeNumberLiteral 1)) (LiteralPattern () (WholeNumberLiteral 2))) (ref "foo")
        , checkIR "\\[] -> foo " <| Lambda () (EmptyListPattern ()) (ref "foo")
        , checkIR "\\[ 1 ] -> foo " <| Lambda () (HeadTailPattern () (LiteralPattern () (WholeNumberLiteral 1)) (EmptyListPattern ())) (ref "foo")
        , checkIR "\\([] as bar) -> foo " <| Lambda () (AsPattern () (EmptyListPattern ()) (Name.fromString "bar")) (ref "foo")
        , checkIR "\\(Foo 1 _) -> foo " <| Lambda () (ConstructorPattern () (fQName [ [ "my" ] ] [ [ "test" ] ] [ "foo" ]) [ LiteralPattern () (WholeNumberLiteral 1), WildcardPattern () ]) (ref "foo")
        , checkIR "\\Bar.Baz -> foo " <| Lambda () (ConstructorPattern () (fQName [ [ "my" ] ] [ [ "bar" ] ] [ "baz" ]) []) (ref "foo")
        , checkIR "case a of\n  1 -> foo\n  _ -> bar" <| PatternMatch () (ref "a") [ ( LiteralPattern () (WholeNumberLiteral 1), ref "foo" ), ( WildcardPattern (), ref "bar" ) ]
        , checkIR "a <| b" <| Apply () (ref "a") (ref "b")
        , checkIR "a |> b" <| Apply () (ref "b") (ref "a")
        , checkIR "a |> b |> c" <| Apply () (ref "c") (Apply () (ref "b") (ref "a"))
        , checkIR "a |> b |> c |> d" <| Apply () (ref "d") (Apply () (ref "c") (Apply () (ref "b") (ref "a")))
        , checkIR "a |> b |> c |> d |> e" <| Apply () (ref "e") (Apply () (ref "d") (Apply () (ref "c") (Apply () (ref "b") (ref "a"))))
        , checkIR "a || b" <| binary SDKBasics.or (ref "a") (ref "b")
        , checkIR "a && b" <| binary SDKBasics.and (ref "a") (ref "b")
        , checkIR "a == b" <| binary SDKBasics.equal (ref "a") (ref "b")
        , checkIR "a /= b" <| binary SDKBasics.notEqual (ref "a") (ref "b")
        , checkIR "a < b" <| binary SDKBasics.lessThan (ref "a") (ref "b")
        , checkIR "a > b" <| binary SDKBasics.greaterThan (ref "a") (ref "b")
        , checkIR "a <= b" <| binary SDKBasics.lessThanOrEqual (ref "a") (ref "b")
        , checkIR "a >= b" <| binary SDKBasics.greaterThanOrEqual (ref "a") (ref "b")
        , checkIR "a + b" <| binary SDKBasics.add (ref "a") (ref "b")
        , checkIR "a - b" <| binary SDKBasics.subtract (ref "a") (ref "b")
        , checkIR "a * b" <| binary SDKBasics.multiply (ref "a") (ref "b")
        , checkIR "a / b" <| binary SDKBasics.divide (ref "a") (ref "b")
        , checkIR "a // b" <| binary SDKBasics.integerDivide (ref "a") (ref "b")
        , checkIR "a ^ b" <| binary SDKBasics.power (ref "a") (ref "b")
        , checkIR "a << b" <| binary SDKBasics.composeLeft (ref "a") (ref "b")
        , checkIR "a >> b" <| binary SDKBasics.composeRight (ref "a") (ref "b")
        , checkIR "a :: b" <| binary List.construct (ref "a") (ref "b")
        , checkIR "(::)" <| List.construct ()
        , checkIR "foo (::)" <| Apply () (ref "foo") (List.construct ())
        , checkIR
            (String.join "\n"
                [ "  let"
                , "    ( a, b ) = c"
                , "  in"
                , "  d"
                ]
            )
          <|
            Destructure ()
                (TuplePattern () [ pvar "a", pvar "b" ])
                (ref "c")
                (ref "d")
        , checkIR
            (String.join "\n"
                [ "  let"
                , "    foo : Int -> Int"
                , "    foo a = c"
                , "  in"
                , "  d"
                ]
            )
          <|
            LetDefinition ()
                (Name.fromString "foo")
                (Definition [ ( Name.fromString "a", (), SDKBasics.intType () ) ] (SDKBasics.intType ()) (ref "c"))
                (ref "d")
        , checkIR
            (String.join "\n"
                [ "  let"
                , "    ( a, b ) = c"
                , "    ( d, e ) = a"
                , "  in"
                , "  f"
                ]
            )
          <|
            Destructure ()
                (TuplePattern () [ pvar "a", pvar "b" ])
                (ref "c")
                (Destructure ()
                    (TuplePattern () [ pvar "d", pvar "e" ])
                    (var "a")
                    (ref "f")
                )
        , checkIR
            (String.join "\n"
                [ "  let"
                , "    ( d, e ) = a"
                , "    ( a, b ) = c"
                , "  in"
                , "  f"
                ]
            )
          <|
            Destructure ()
                (TuplePattern () [ pvar "a", pvar "b" ])
                (ref "c")
                (Destructure ()
                    (TuplePattern () [ pvar "d", pvar "e" ])
                    (var "a")
                    (ref "f")
                )
        , checkIR
            (String.join "\n"
                [ "  let"
                , "    b : Int"
                , "    b = c"
                , "    a : Int"
                , "    a = b"
                , "  in"
                , "  a"
                ]
            )
          <|
            LetDefinition ()
                (Name.fromString "b")
                (Definition [] (SDKBasics.intType ()) (ref "c"))
                (LetDefinition ()
                    (Name.fromString "a")
                    (Definition [] (SDKBasics.intType ()) (var "b"))
                    (var "a")
                )
        , checkIR
            (String.join "\n"
                [ "  let"
                , "    a : Int"
                , "    a = b"
                , "    b : Int"
                , "    b = c"
                , "  in"
                , "  a"
                ]
            )
          <|
            LetDefinition ()
                (Name.fromString "b")
                (Definition [] (SDKBasics.intType ()) (ref "c"))
                (LetDefinition ()
                    (Name.fromString "a")
                    (Definition [] (SDKBasics.intType ()) (var "b"))
                    (var "a")
                )
        , checkIR
            (String.join "\n"
                [ "  let"
                , "    a : Int"
                , "    a = b"
                , "    b : Int"
                , "    b = a"
                , "  in"
                , "  a"
                ]
            )
          <|
            LetRecursion ()
                (Dict.fromList
                    [ ( Name.fromString "b", Definition [] (SDKBasics.intType ()) (var "a") )
                    , ( Name.fromString "a", Definition [] (SDKBasics.intType ()) (var "b") )
                    ]
                )
                (var "a")
        , checkIR
            (String.join "\n"
                [ "  let"
                , "    c : Int"
                , "    c = d"
                , "    a : Int"
                , "    a = b"
                , "    b : Int"
                , "    b = a"
                , "  in"
                , "  a"
                ]
            )
          <|
            LetDefinition ()
                (Name.fromString "c")
                (Definition [] (SDKBasics.intType ()) (ref "d"))
                (LetRecursion ()
                    (Dict.fromList
                        [ ( Name.fromString "b", Definition [] (SDKBasics.intType ()) (var "a") )
                        , ( Name.fromString "a", Definition [] (SDKBasics.intType ()) (var "b") )
                        ]
                    )
                    (var "a")
                )
        ]


resultToExpectation : a -> Result String a -> Expectation
resultToExpectation expectedValue result =
    case result of
        Ok actualValue ->
            Expect.equal expectedValue actualValue

        Err error ->
            Expect.fail error
