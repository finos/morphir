module Morphir.Scala.JSONBackendTests exposing (..)

import Expect
import Morphir.IR.Type as Type
import Morphir.Scala.AST as Scala
import Morphir.Scala.JSONBackend exposing (mapTypeDefinition)
import Morphir.Scala.PrettyPrinter as PrettyPrinter
import Test exposing (Test, describe, test)


mapTypeDefinitionTests : Test
mapTypeDefinitionTests =
    let
        positiveTest name fqn input expectedOutput =
            test name
                (\_ ->
                    case mapTypeDefinition fqn input of
                        Ok output ->
                            output
                                |> List.map (PrettyPrinter.mapMemberDecl (PrettyPrinter.Options 2 80))
                                |> Expect.equal expectedOutput

                        Err error ->
                            Expect.fail error
                )
    in
    describe "mapTypeDefinition"
        [ positiveTest "simple reference"
            ( [ [ "test" ], [ "pack" ] ], [ [ "test" ], [ "mod" ] ], [ "foo" ] )
            (Type.TypeAliasDefinition [] (Type.Reference () ( [ [ "test" ], [ "pack" ] ], [ [ "test" ], [ "mod" ] ], [ "bar" ] ) []))
            [ "val encodeFoo: io.circe.Encoder[test.pack.test.Mod.Foo] = test.pack.test.mod.Codec.encodeBar" ]
        ]
