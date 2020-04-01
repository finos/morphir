module Morphir.Elm.FrontendTests exposing (..)

import Dict
import Expect exposing (Expectation)
import Morphir.Elm.Frontend as Frontend exposing (Errors, SourceFile, SourceLocation)
import Morphir.IR.AccessControlled exposing (AccessControlled, private, public)
import Morphir.IR.FQName exposing (fQName)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Bool as Bool
import Morphir.IR.SDK.Float as Float
import Morphir.IR.SDK.Int as Int
import Morphir.IR.SDK.List as List
import Morphir.IR.SDK.Maybe as Maybe
import Morphir.IR.SDK.Number as Number
import Morphir.IR.SDK.String as String
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value exposing (Literal(..), Value(..))
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
                                                    [ ( [ "foo" ]
                                                      , [ ( [ "arg", "1" ], Type.Reference () (fQName packageName [ [ "b" ] ] [ "bee" ]) [] )
                                                        ]
                                                      )
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
                                                (public [ ( [ "bee" ], [] ) ])
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
                |> Result.map Package.eraseDefinitionExtra
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
                        |> Result.map Package.eraseDefinitionExtra
                        |> Result.mapError (\error -> "Error while reading model")
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
        ]


resultToExpectation : a -> Result String a -> Expectation
resultToExpectation expectedValue result =
    case result of
        Ok actualValue ->
            Expect.equal expectedValue actualValue

        Err error ->
            Expect.fail error
