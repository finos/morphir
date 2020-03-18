module Morphir.Elm.FrontendTests exposing (..)

import Dict
import Expect
import Morphir.Elm.Frontend as Frontend exposing (SourceLocation)
import Morphir.IR.AccessControlled exposing (AccessControlled, private, public)
import Morphir.IR.Advanced.Package as Package
import Morphir.IR.Advanced.Type as Type
import Morphir.IR.FQName exposing (fQName)
import Morphir.IR.Path as Path
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

        packageName =
            Path.fromString "my/package"

        moduleA =
            Path.fromString "My.Package.A"

        moduleB =
            Path.fromString "My.Package.B"

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
            Frontend.packageDefinitionFromSource packageInfo [ sourceA, sourceB ]
                |> Result.map Package.eraseDefinitionExtra
                |> Expect.equal (Ok expected)


unindent : String -> String
unindent text =
    text
