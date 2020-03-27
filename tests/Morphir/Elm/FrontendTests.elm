module Morphir.Elm.FrontendTests exposing (..)

import Dict
import Expect
import Morphir.Elm.Frontend as Frontend exposing (Errors, SourceFile, SourceLocation)
import Morphir.IR.AccessControlled exposing (AccessControlled, private, public)
import Morphir.IR.Advanced.Package as Package
import Morphir.IR.Advanced.Type as Type
import Morphir.IR.Advanced.Value as Value exposing (Definition(..), Literal(..), Value(..))
import Morphir.IR.FQName exposing (fQName)
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Bool as Bool
import Morphir.IR.SDK.Float as Float
import Morphir.IR.SDK.Int as Int
import Morphir.IR.SDK.List as List
import Morphir.IR.SDK.Maybe as Maybe
import Morphir.IR.SDK.String as String
import Set
import Test exposing (..)


frontendTest : Test
frontendTest =
    let
        sourceA =
            { path = "My/Package/A.elm"
            , content =
                unindent """
module My.Package.A exposing (..)

import My.Package.B exposing (Bee)

type Foo = Foo Bee

type alias Bar = Foo

type alias Rec =
    { field1 : Foo
    , field2 : Bar
    , field3 : Bool
    , field4 : Int
    , field5 : Float
    , field6 : String
    , field7 : Maybe Int
    , field8 : List Float
    }
                """
            }

        sourceB =
            { path = "My/Package/B.elm"
            , content =
                unindent """
module My.Package.B exposing (..)

type Bee = Bee
                """
            }

        sourceC =
            { path = "My/Package/C.elm"
            , content =
                unindent """
module My.Package.C exposing (..)

type Cee = Cee
                """
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
                                            (Type.typeAliasDefinition []
                                                (Type.reference (fQName packageName [ [ "a" ] ] [ "foo" ]) [] ())
                                            )
                                      )
                                    , ( [ "foo" ]
                                      , public
                                            (Type.customTypeDefinition []
                                                (public
                                                    [ ( [ "foo" ]
                                                      , [ ( [ "arg", "1" ], Type.reference (fQName packageName [ [ "b" ] ] [ "bee" ]) [] () )
                                                        ]
                                                      )
                                                    ]
                                                )
                                            )
                                      )
                                    , ( [ "rec" ]
                                      , public
                                            (Type.typeAliasDefinition []
                                                (Type.record
                                                    [ Type.Field [ "field", "1" ]
                                                        (Type.reference (fQName packageName [ [ "a" ] ] [ "foo" ]) [] ())
                                                    , Type.Field [ "field", "2" ]
                                                        (Type.reference (fQName packageName [ [ "a" ] ] [ "bar" ]) [] ())
                                                    , Type.Field [ "field", "3" ]
                                                        (Bool.boolType ())
                                                    , Type.Field [ "field", "4" ]
                                                        (Int.intType ())
                                                    , Type.Field [ "field", "5" ]
                                                        (Float.floatType ())
                                                    , Type.Field [ "field", "6" ]
                                                        (String.stringType ())
                                                    , Type.Field [ "field", "7" ]
                                                        (Maybe.maybeType (Int.intType ()) ())
                                                    , Type.Field [ "field", "8" ]
                                                        (List.listType (Float.floatType ()) ())
                                                    ]
                                                    ()
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
                                            (Type.customTypeDefinition []
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



--valueTests : Test
--valueTests =
--    let
--        packageInfo =
--            { name = []
--            , exposedModules = Set.empty
--            }
--
--        moduleSource : String -> SourceFile
--        moduleSource sourceValue =
--            { path = "Test.elm"
--            , content =
--                String.join "\n"
--                    [ "module Test exposing (..)"
--                    , ""
--                    , "testValue = " ++ sourceValue
--                    ]
--            }
--
--        checkIR : String -> Value () -> Test
--        checkIR valueSource expectedValueIR =
--            test valueSource <|
--                \_ ->
--                    Frontend.packageDefinitionFromSource packageInfo [ moduleSource valueSource ]
--                        |> Result.map Package.eraseDefinitionExtra
--                        |> Result.toMaybe
--                        |> Maybe.andThen
--                            (\packageDef ->
--                                packageDef.modules
--                                    |> Dict.get [ [ "test" ] ]
--                                    |> Maybe.andThen
--                                        (\moduleDef ->
--                                            moduleDef.value.values
--                                                |> Dict.get [ "test", "value" ]
--                                                |> Maybe.map (.value >> Value.getDefinitionBody)
--                                        )
--                            )
--                        |> Maybe.map (Expect.equal expectedValueIR)
--                        |> Maybe.withDefault (Expect.fail "Could not find the value in the IR")
--    in
--    describe "Values are mapped correctly"
--        [ checkIR "1" <| Literal (IntLiteral 1) ()
--        ]
--


unindent : String -> String
unindent text =
    text
