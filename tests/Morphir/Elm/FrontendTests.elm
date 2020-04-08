module Morphir.Elm.FrontendTests exposing (..)

import Dict
import Expect exposing (Expectation)
import Morphir.Elm.Frontend as Frontend exposing (Errors, SourceFile, SourceLocation)
import Morphir.IR.AccessControlled exposing (AccessControlled, private, public)
import Morphir.IR.FQName exposing (fQName)
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Appending as Appending
import Morphir.IR.SDK.Bool as Bool
import Morphir.IR.SDK.Comparison as Comparison
import Morphir.IR.SDK.Composition as Composition
import Morphir.IR.SDK.Equality as Equality
import Morphir.IR.SDK.Float as Float
import Morphir.IR.SDK.Int as Int
import Morphir.IR.SDK.List as List
import Morphir.IR.SDK.Maybe as Maybe
import Morphir.IR.SDK.Number as Number
import Morphir.IR.SDK.String as String
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value exposing (Literal(..), Pattern(..), Value(..))
import Set
import Test exposing (..)


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
                    , "type Foo = Foo Bee"
                    , ""
                    , "type alias Bar = Foo"
                    , ""
                    , "type alias Rec ="
                    , "    { field1 : Foo"
                    , "    , field2 : Bar"
                    , "    , field3 : Bool"
                    , "    , field4 : Int"
                    , "    , field5 : Float"
                    , "    , field6 : String"
                    , "    , field7 : Maybe Int"
                    , "    , field8 : List Float"
                    , "    }"
                    ]
            }

        sourceB =
            { path = "My/Package/B.elm"
            , content =
                String.join "\n"
                    [ "module My.Package.B exposing (..)"
                    , ""
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
                Set.fromList
                    [ moduleA
                    ]
            }

        expected : Package.Definition ()
        expected =
            { dependencies = Dict.empty
            , modules =
                Dict.fromList
                    [ ( moduleA
                      , public
                            { types =
                                Dict.fromList
                                    [ ( [ "bar" ]
                                      , public
                                            (Type.TypeAliasDefinition []
                                                (Type.Reference () (fQName packageName [ [ "a" ] ] [ "foo" ]) [])
                                            )
                                      )
                                    , ( [ "foo" ]
                                      , public
                                            (Type.CustomTypeDefinition []
                                                (public
                                                    [ Type.Constructor [ "foo" ]
                                                        [ ( [ "arg", "1" ], Type.Reference () (fQName packageName [ [ "b" ] ] [ "bee" ]) [] )
                                                        ]
                                                    ]
                                                )
                                            )
                                      )
                                    , ( [ "rec" ]
                                      , public
                                            (Type.TypeAliasDefinition []
                                                (Type.Record ()
                                                    [ Type.Field [ "field", "1" ]
                                                        (Type.Reference () (fQName packageName [ [ "a" ] ] [ "foo" ]) [])
                                                    , Type.Field [ "field", "2" ]
                                                        (Type.Reference () (fQName packageName [ [ "a" ] ] [ "bar" ]) [])
                                                    , Type.Field [ "field", "3" ]
                                                        (Bool.boolType ())
                                                    , Type.Field [ "field", "4" ]
                                                        (Int.intType ())
                                                    , Type.Field [ "field", "5" ]
                                                        (Float.floatType ())
                                                    , Type.Field [ "field", "6" ]
                                                        (String.stringType ())
                                                    , Type.Field [ "field", "7" ]
                                                        (Maybe.maybeType () (Int.intType ()))
                                                    , Type.Field [ "field", "8" ]
                                                        (List.listType () (Float.floatType ()))
                                                    ]
                                                )
                                            )
                                      )
                                    ]
                            , values =
                                Dict.empty
                            }
                      )
                    , ( moduleB
                      , private
                            { types =
                                Dict.fromList
                                    [ ( [ "bee" ]
                                      , public
                                            (Type.CustomTypeDefinition []
                                                (public [ Type.Constructor [ "bee" ] [] ])
                                            )
                                      )
                                    ]
                            , values =
                                Dict.empty
                            }
                      )
                    ]
            }
    in
    test "first" <|
        \_ ->
            Frontend.packageDefinitionFromSource packageInfo [ sourceA, sourceB, sourceC ]
                |> Result.map Package.eraseDefinitionAttributes
                |> Expect.equal (Ok expected)


valueTests : Test
valueTests =
    let
        packageInfo =
            { name = []
            , exposedModules = Set.fromList [ [ [ "test" ] ] ]
            }

        moduleSource : String -> SourceFile
        moduleSource sourceValue =
            { path = "Test.elm"
            , content =
                String.join "\n"
                    [ "module Test exposing (..)"
                    , ""
                    , "testValue = " ++ sourceValue
                    ]
            }

        checkIR : String -> Value () -> Test
        checkIR valueSource expectedValueIR =
            test valueSource <|
                \_ ->
                    Frontend.packageDefinitionFromSource packageInfo [ moduleSource valueSource ]
                        |> Result.map Package.eraseDefinitionAttributes
                        |> Result.mapError
                            (\errors ->
                                errors
                                    |> List.map
                                        (\error ->
                                            case error of
                                                Frontend.ParseError _ _ ->
                                                    "Parse Error"

                                                Frontend.CyclicModules _ ->
                                                    "Cyclic Modules"

                                                Frontend.ResolveError _ _ ->
                                                    "Resolve Error"

                                                Frontend.EmptyApply _ ->
                                                    "Empty Apply"

                                                Frontend.NotSupported _ expType ->
                                                    "Not Supported: " ++ expType
                                        )
                                    |> String.join ", "
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
                                                |> Result.map (.value >> Value.getDefinitionBody)
                                        )
                            )
                        |> resultToExpectation expectedValueIR

        ref : String -> Value ()
        ref name =
            Reference () (fQName [] [] [ name ])
    in
    describe "Values are mapped correctly"
        [ checkIR "()" <| Unit ()
        , checkIR "1" <| Literal () (IntLiteral 1)
        , checkIR "0x20" <| Literal () (IntLiteral 32)
        , checkIR "1.5" <| Literal () (FloatLiteral 1.5)
        , checkIR "\"foo\"" <| Literal () (StringLiteral "foo")
        , checkIR "True" <| Literal () (BoolLiteral True)
        , checkIR "False" <| Literal () (BoolLiteral False)
        , checkIR "'A'" <| Literal () (CharLiteral 'A')
        , checkIR "foo" <| ref "foo"
        , checkIR "Bar.foo" <| Reference () (fQName [] [ [ "bar" ] ] [ "foo" ])
        , checkIR "MyPack.Bar.foo" <| Reference () (fQName [] [ [ "my", "pack" ], [ "bar" ] ] [ "foo" ])
        , checkIR "foo bar" <| Apply () (ref "foo") (ref "bar")
        , checkIR "foo bar baz" <| Apply () (Apply () (ref "foo") (ref "bar")) (ref "baz")
        , checkIR "-1" <| Number.negate () () (Literal () (IntLiteral 1))
        , checkIR "if foo then bar else baz" <| IfThenElse () (ref "foo") (ref "bar") (ref "baz")
        , checkIR "( foo, bar, baz )" <| Tuple () [ ref "foo", ref "bar", ref "baz" ]
        , checkIR "( foo )" <| ref "foo"
        , checkIR "[ foo, bar, baz ]" <| List () [ ref "foo", ref "bar", ref "baz" ]
        , checkIR "{ foo = foo, bar = bar, baz = baz }" <| Record () [ ( [ "foo" ], ref "foo" ), ( [ "bar" ], ref "bar" ), ( [ "baz" ], ref "baz" ) ]
        , checkIR "foo.bar" <| Field () (ref "foo") [ "bar" ]
        , checkIR ".bar" <| FieldFunction () [ "bar" ]
        , checkIR "{ a | foo = foo, bar = bar }" <| UpdateRecord () (Variable () [ "a" ]) [ ( [ "foo" ], ref "foo" ), ( [ "bar" ], ref "bar" ) ]
        , checkIR "\\() -> foo " <| Lambda () (UnitPattern ()) (ref "foo")
        , checkIR "\\() () -> foo " <| Lambda () (UnitPattern ()) (Lambda () (UnitPattern ()) (ref "foo"))
        , checkIR "\\_ -> foo " <| Lambda () (WildcardPattern ()) (ref "foo")
        , checkIR "\\'a' -> foo " <| Lambda () (LiteralPattern () (CharLiteral 'a')) (ref "foo")
        , checkIR "\\\"foo\" -> foo " <| Lambda () (LiteralPattern () (StringLiteral "foo")) (ref "foo")
        , checkIR "\\42 -> foo " <| Lambda () (LiteralPattern () (IntLiteral 42)) (ref "foo")
        , checkIR "\\0x20 -> foo " <| Lambda () (LiteralPattern () (IntLiteral 32)) (ref "foo")
        , checkIR "\\( 1, 2 ) -> foo " <| Lambda () (TuplePattern () [ LiteralPattern () (IntLiteral 1), LiteralPattern () (IntLiteral 2) ]) (ref "foo")
        , checkIR "\\{ foo, bar } -> foo " <| Lambda () (RecordPattern () [ Name.fromString "foo", Name.fromString "bar" ]) (ref "foo")
        , checkIR "\\1 :: 2 -> foo " <| Lambda () (HeadTailPattern () (LiteralPattern () (IntLiteral 1)) (LiteralPattern () (IntLiteral 2))) (ref "foo")
        , checkIR "\\[] -> foo " <| Lambda () (EmptyListPattern ()) (ref "foo")
        , checkIR "\\[ 1 ] -> foo " <| Lambda () (HeadTailPattern () (LiteralPattern () (IntLiteral 1)) (EmptyListPattern ())) (ref "foo")
        , checkIR "\\([] as bar) -> foo " <| Lambda () (AsPattern () (EmptyListPattern ()) (Name.fromString "bar")) (ref "foo")
        , checkIR "\\(Foo 1 _) -> foo " <| Lambda () (ConstructorPattern () (fQName [] [] [ "foo" ]) [ LiteralPattern () (IntLiteral 1), WildcardPattern () ]) (ref "foo")
        , checkIR "\\Foo.Bar.Baz -> foo " <| Lambda () (ConstructorPattern () (fQName [] [ [ "foo" ], [ "bar" ] ] [ "baz" ]) []) (ref "foo")
        , checkIR "case a of\n  1 -> foo\n  _ -> bar" <| PatternMatch () (ref "a") [ ( LiteralPattern () (IntLiteral 1), ref "foo" ), ( WildcardPattern (), ref "bar" ) ]
        , checkIR "a <| b" <| Apply () (ref "a") (ref "b")
        , checkIR "a |> b" <| Apply () (ref "b") (ref "a")
        , checkIR "a || b" <| Bool.or () (ref "a") (ref "b")
        , checkIR "a && b" <| Bool.and () (ref "a") (ref "b")
        , checkIR "a == b" <| Equality.equal () (ref "a") (ref "b")
        , checkIR "a /= b" <| Equality.notEqual () (ref "a") (ref "b")
        , checkIR "a < b" <| Comparison.lessThan () (ref "a") (ref "b")
        , checkIR "a > b" <| Comparison.greaterThan () (ref "a") (ref "b")
        , checkIR "a <= b" <| Comparison.lessThanOrEqual () (ref "a") (ref "b")
        , checkIR "a >= b" <| Comparison.greaterThanOrEqual () (ref "a") (ref "b")
        , checkIR "a ++ b" <| Appending.append () (ref "a") (ref "b")
        , checkIR "a + b" <| Number.add () (ref "a") (ref "b")
        , checkIR "a - b" <| Number.subtract () (ref "a") (ref "b")
        , checkIR "a * b" <| Number.multiply () (ref "a") (ref "b")
        , checkIR "a / b" <| Float.divide () (ref "a") (ref "b")
        , checkIR "a // b" <| Int.divide () (ref "a") (ref "b")
        , checkIR "a ^ b" <| Number.power () (ref "a") (ref "b")
        , checkIR "a << b" <| Composition.composeLeft () (ref "a") (ref "b")
        , checkIR "a >> b" <| Composition.composeRight () (ref "a") (ref "b")
        , checkIR "a :: b" <| List.construct () (ref "a") (ref "b")
        ]


resultToExpectation : a -> Result String a -> Expectation
resultToExpectation expectedValue result =
    case result of
        Ok actualValue ->
            Expect.equal expectedValue actualValue

        Err error ->
            Expect.fail error
