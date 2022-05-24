module Morphir.Scala.JSONBackendTests exposing (..)

import Expect
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.Type as Type
import Morphir.Scala.AST as Scala exposing (ArgValue(..), Generator(..), Lit(..), Pattern(..), Value(..))
import Morphir.Scala.Feature.Codec exposing (genDecodeReference, genEncodeReference, mapTypeDefinitionToDecoder, mapTypeDefinitionToEncoder)
import Morphir.Scala.PrettyPrinter as PrettyPrinter
import Test exposing (Test, describe, test)


--mapTypeDefinitionToEncoderTests : Test
--mapTypeDefinitionToEncoderTests =
--    let
--        positiveTest name fqn input expectedOutput =
--            test name
--                (\_ ->
--                    case mapTypeDefinitionToEncoder fqn input of
--                        Ok [] ->
--                            []
--                                |> List.map (PrettyPrinter.mapMemberDecl (PrettyPrinter.Options 2 80))
--                                |> Expect.equal expectedOutput
--
--                        Err error ->
--                            Expect.fail error
--                )
--    in
--    describe "Map Type Definition to Encoder Test"
        [ --positiveTest "Record type with 2 fields (String, Int)"
        --    ( [ [ "test" ], [ "pack" ] ], [ [ "test" ], [ "mod" ] ], [ "Employee" ] )
        --    (Type.TypeAliasDefinition []
        --        (Type.Record ()
        --            [ Type.Field [ "name" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "String") [])
        --            , Type.Field [ "age" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "Int") [])
        --            ]
        --        )
        --    )
        --    [ "val encodeEmployee: io.circe.Encoder[test.pack.test.Mod.Employee] = (a: test.pack.test.Mod.Employee) =>\n  io.circe.Json.obj(\n    (\"name\", morphir.sdk.basics.Codec.encodeString(a.name)),\n    (\"age\", morphir.sdk.basics.Codec.encodeInt(a.age))\n  )"
        --    ]
        --, positiveTest "Record type with 3 fields (String, Int, String)"
        --    ( [ [ "test" ], [ "pack" ] ], [ [ "test" ], [ "mod" ] ], [ "Employee" ] )
        --    (Type.TypeAliasDefinition []
        --        (Type.Record ()
        --            [ Type.Field [ "name" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "String") [])
        --            , Type.Field [ "age" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "Int") [])
        --            , Type.Field [ "department" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "String") [])
        --            ]
        --        )
        --    )
        --    [ "val encodeEmployee: io.circe.Encoder[test.pack.test.Mod.Employee] = (a: test.pack.test.Mod.Employee) =>\n  io.circe.Json.obj(\n    (\"name\", morphir.sdk.basics.Codec.encodeString(a.name)),\n    (\"age\", morphir.sdk.basics.Codec.encodeInt(a.age)),\n    (\"department\", morphir.sdk.basics.Codec.encodeString(a.department))\n  )" ]
        ]


--mapTypeDefinitionToDecoderTests : Test
--mapTypeDefinitionToDecoderTests =
--    let
--        positiveTest name fqn inputRec expectedOutput =
--            test name
--                (\_ ->
--                    case mapTypeDefinitionToDecoder fqn inputRec of
--                        Ok output ->
--                            output
--                                |> List.map (PrettyPrinter.mapMemberDecl (PrettyPrinter.Options 2 80))
--                                |> Expect.equal expectedOutput
--
--                        Err error ->
--                            Expect.fail error
--                )
--    in
--    describe "Map Type Definition to Decoder Tests "
--        [ -- positiveTest "1. Record with 2 Fields"
--        --    ( [ [ "test" ], [ "pack" ] ], [ [ "test" ], [ "mod" ] ], [ "Foo" ] )
--        --    (Type.TypeAliasDefinition []
--        --        (Type.Record ()
--        --            [ Type.Field [ "rate" ] (Type.Reference () (fqn "morphir" "sdk" "string") [])
--        --            , Type.Field [ "age" ] (Type.Reference () (fqn "morphir" "sdk" "Int") [])
--        --            ]
--        --        )
--        --    )
--        --    [ "val decodeFoo: io.circe.Decoder[test.pack.test.Mod.Foo] = (c: io.circe.HCursor) =>\n  for {\n    rate <- c.downField(\"rate\").as(morphir.sdk.Codec.decodeString)\n    age <- c.downField(\"age\").as(morphir.sdk.Codec.decodeInt)\n  }  yield test.pack.test.Mod.Foo(\n    rate,\n    age\n  )" ]
--        ]
--

genEncodeReferenceTests : Test
genEncodeReferenceTests =
    let
        postiveTest name inputData outputData =
            test name
                (\_ ->
                    case genEncodeReference inputData of
                        Ok output ->
                            output
                                |> Expect.equal outputData

                        Err error ->
                            Expect.fail error
                )
    in
    describe "Generate Encoder Reference Tests"
        [ postiveTest "1. Type Variable "
            (Type.Variable () [ "foo" ])
            (Scala.Variable "encodeFoo")
        , postiveTest "2. Type Reference"
            (Type.Reference () (fqn "morphir" "sdk" "string") [])
            (Scala.Ref [ "morphir", "sdk", "Codec" ] "encodeString")
        --, postiveTest "3. Type Record with two fields"
        --    (Type.Record ()
        --        [ Type.Field [ "name" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "String") [])
        --        , Type.Field [ "age" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "Int") [])
        --        ]
        --    )
        --    (Scala.Apply (Scala.Ref [ "io", "circe", "Json" ] "obj")
        --        [ Scala.ArgValue Nothing
        --            (Scala.Tuple
        --                [ Scala.Literal (Scala.StringLit "name")
        --                , Scala.Apply (Scala.Ref [ "morphir", "sdk", "basics", "Codec" ] "encodeString") [ ArgValue Nothing (Select (Variable "a") "name") ]
        --                ]
        --            )
        --        , Scala.ArgValue Nothing
        --            (Scala.Tuple
        --                [ Scala.Literal (Scala.StringLit "age")
        --                , Scala.Apply (Scala.Ref [ "morphir", "sdk", "basics", "Codec" ] "encodeInt") [ ArgValue Nothing (Select (Variable "a") "age") ]
        --                ]
        --            )
        --        ]
        --    )
        ]


genDecodeReferenceTests : Test
genDecodeReferenceTests =
    let
        positiveTest name inputRef outputRef =
            test name
                (\_ ->
                    case genDecodeReference (fqn "Morphir" "sdk" "Foo") inputRef of
                        Ok output ->
                            output
                                |> Expect.equal outputRef

                        Err error ->
                            Expect.fail error
                )
    in
    describe "Generate Decoder Reference Test"
        [ positiveTest "1. Type Variable "
            (Type.Variable () [ "foo" ])
            (Scala.Variable "decodeFoo")
        , positiveTest "2. Type Reference"
            (Type.Reference () (fqn "foo" "bar" "baz") [])
            (Scala.Ref [ "foo", "bar", "Codec" ] "decodeBaz")
        --, positiveTest "3. Type Record"
        --    (Type.Record ()
        --        [ Type.Field [ "name" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "String") [])
        --        , Type.Field [ "age" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "Int") [])
        --        ]
        --    )
        --    (ForComp
        --        [ Extract (NamedMatch "name") (Apply (Select (Apply (Select (Variable "c") "downField") [ ArgValue Nothing (Literal (StringLit "name")) ]) "as") [ ArgValue Nothing (Ref [ "morphir", "sdk", "basics", "Codec" ] "decodeString") ])
        --        , Extract (NamedMatch "age") (Apply (Select (Apply (Select (Variable "c") "downField") [ ArgValue Nothing (Literal (StringLit "age")) ]) "as") [ ArgValue Nothing (Ref [ "morphir", "sdk", "basics", "Codec" ] "decodeInt") ])
        --        ]
        --        (Apply (Ref [ "morphir", "Sdk" ] "foo") [ ArgValue Nothing (Variable "name"), ArgValue Nothing (Variable "age") ])
        --    )
        ]
