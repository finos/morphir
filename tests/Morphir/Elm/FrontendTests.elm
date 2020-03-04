module Morphir.Elm.FrontendTests exposing (..)

import Dict
import Expect
import Morphir.DAG as DAG
import Morphir.Elm.Frontend as Frontend exposing (SourceLocation)
import Morphir.IR.AccessControlled exposing (AccessControlled, private, public)
import Morphir.IR.Advanced.Module as Module
import Morphir.IR.Advanced.Package as Package
import Set
import Test exposing (..)


frontendTest : Test
frontendTest =
    let
        source =
            { path = "A.elm"
            , content =
                unindent """
module A exposing (..)

type Foo = Foo

type alias Bar = Foo
                """
            }

        expected : Package.Definition ()
        expected =
            { dependencies = Dict.empty
            , modules =
                Dict.fromList
                    [ ( [ [ "a" ] ]
                      , public
                            { types = Dict.empty
                            , values = Dict.empty
                            }
                      )
                    ]
            }
    in
    test "first" <|
        \_ ->
            Frontend.initFromSource [ [ "my" ], [ "package" ] ] [ source ]
                |> Result.map Package.eraseDefinitionExtra
                |> Expect.equal (Ok expected)


unindent : String -> String
unindent text =
    text
