module Morphir.Scala.Feature.CodecTests exposing (..)

import Dict
import Expect
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.Type as Type exposing (Definition(..), Type)
import Morphir.Scala.AST as Scala exposing (ArgValue(..), Generator(..), Lit(..), Pattern(..), Value(..))
import Morphir.Scala.Feature.Codec exposing (genDecodeReference, genEncodeReference, mapTypeDefinitionToEncoder)
import Test exposing (Test, describe, test)


genEncodeReferenceTests : Test
genEncodeReferenceTests =
    let
        positiveTest name input expectedOutput =
            test name
                (\_ ->
                    case genEncodeReference input of
                        Ok output ->
                            output
                                |> Expect.equal expectedOutput

                        Err error ->
                            Expect.fail error
                )
    in
    describe "Generate Encoder Reference Tests"
        [ positiveTest "1. Type Variable "
            (Type.Variable () [ "foo" ])
            (Scala.Variable "encodeFoo")
        , positiveTest "2. Type Reference"
            (Type.Reference () (fqn "morphir" "sdk" "string") [])
            (Scala.Ref [ "morphir", "sdk" ] "encodeString")
        , positiveTest "3. Type Record with two fields"
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
        , positiveTest "4. Type Record with three fields"
            (Type.Record ()
                [ Type.Field [ "firstname" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "String") [])
                , Type.Field [ "lastname" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "String") [])
                , Type.Field [ "age" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "Int") [])
                ]
            )
            (Scala.Apply (Scala.Ref [ "io", "circe", "Json" ] "obj")
                [ Scala.ArgValue Nothing
                    (Scala.Tuple
                        [ Scala.Literal (Scala.StringLit "firstname")
                        , Scala.Apply (Scala.Ref [ "morphir", "sdk", "basics" ] "encodeString") [ ArgValue Nothing (Select (Variable "a") "firstname") ]
                        ]
                    )
                , Scala.ArgValue Nothing
                    (Scala.Tuple
                        [ Scala.Literal (Scala.StringLit "lastname")
                        , Scala.Apply (Scala.Ref [ "morphir", "sdk", "basics" ] "encodeString") [ ArgValue Nothing (Select (Variable "a") "lastname") ]
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
        , positiveTest "4. Tuple with 2 fields"
            (Type.Tuple () [ Type.Reference () (fqn "morphir.sdk" "basics" "string") [] ])
            (Scala.Apply (Scala.Variable "io.circe.arr") [ ArgValue Nothing (Scala.Ref [ "morphir", "sdk", "basics" ] "encodeString") ])
        ]


{-| -}
mapTypeDefinitionToEncoderTests : Test
mapTypeDefinitionToEncoderTests =
    let
        positiveTest name currentPackagePath currentModulePath accessControlledModuleDef ( typeName, accessControlledDocumentedTypeDef ) outputResult =
            test name
                (\_ ->
                    case mapTypeDefinitionToEncoder currentPackagePath currentModulePath accessControlledModuleDef ( typeName, accessControlledDocumentedTypeDef ) of
                        Ok output ->
                            output
                                |> Expect.equal outputResult

                        Err error ->
                            Expect.fail error
                )

        accTypeDef : AccessControlled (Documented (Definition ()))
        accTypeDef =
            Documented "" (TypeAliasDefinition [ [ "foo" ] ] (Type.Unit ()))
                |> AccessControlled Public

        accModDef =
            AccessControlled Public { values = Dict.empty, types = Dict.singleton [ "foo" ] accTypeDef }
    in
    describe "Tests for Generate Encoders for Custom Types"
        [ positiveTest "Empty Type Definition"
            []
            []
            accModDef
            ( [ "foo" ], accTypeDef )
            [ Scala.withoutAnnotation
                (Scala.ValueDecl
                    { modifiers = [ Scala.Implicit ]
                    , pattern = Scala.NamedMatch "foo"
                    , valueType = Nothing
                    , value = Scala.Variable "foo"
                    }
                )
            ]
        , positiveTest "Empty another Definition"
            []
            []
            accModDef
            ( [ "foo" ], accTypeDef )
            [ Scala.withoutAnnotation
                (Scala.ValueDecl
                    { modifiers = [ Scala.Implicit ]
                    , pattern = Scala.NamedMatch "foo"
                    , valueType = Nothing
                    , value = Scala.Variable "foo"
                    }
                )
            ]
        ]
