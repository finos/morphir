module Morphir.Scala.Feature.CodecTests exposing (..)

import Expect
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.Type as Type
import Morphir.Scala.AST as Scala exposing (ArgValue(..), Generator(..), Lit(..), Pattern(..), Value(..))
import Morphir.Scala.Feature.Codec exposing (genDecodeReference, genEncodeReference)
import Test exposing (Test, describe, test)


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
            (Scala.Ref [ "morphir", "sdk" ] "encodeString")
        , postiveTest "3. Type Record with two fields"
            (Type.Record ()
                [ Type.Field [ "name" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "String") [])
                , Type.Field [ "age" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "Int") [])
                ]
            )
            (Scala.Apply (Scala.Ref [ "io", "circe", "Json" ] "obj")
                [ Scala.ArgValue Nothing
                    (Scala.Tuple
                        [ Scala.Literal (Scala.StringLit "name")
                        , Scala.Apply (Scala.Ref [ "morphir", "sdk", "basics" ] "encodeString") [ ArgValue Nothing (Select (Variable "a") "name") ]
                        ]
                    )
                , Scala.ArgValue Nothing
                    (Scala.Tuple
                        [ Scala.Literal (Scala.StringLit "age")
                        , Scala.Apply (Scala.Ref [ "morphir", "sdk", "basics" ] "encodeInt") [ ArgValue Nothing (Select (Variable "a") "age") ]
                        ]
                    )
                ]
            )
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
        , positiveTest "3. Type Record"
            (Type.Record ()
                [ Type.Field [ "name" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "String") [])
                , Type.Field [ "age" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "Int") [])
                ]
            )
            (ForComp
                [ Extract (NamedMatch "name") (Apply (Select (Apply (Select (Variable "c") "downField") [ ArgValue Nothing (Literal (StringLit "name")) ]) "as") [ ArgValue Nothing (Ref [ "morphir", "sdk", "basics", "Codec" ] "decodeString") ])
                , Extract (NamedMatch "age") (Apply (Select (Apply (Select (Variable "c") "downField") [ ArgValue Nothing (Literal (StringLit "age")) ]) "as") [ ArgValue Nothing (Ref [ "morphir", "sdk", "basics", "Codec" ] "decodeInt") ])
                ]
                (Apply (Ref [ "morphir", "Sdk" ] "foo") [ ArgValue Nothing (Variable "name"), ArgValue Nothing (Variable "age") ])
            )
        ]
