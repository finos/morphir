module Morphir.Scala.Feature.CodecTests exposing (..)

import Dict
import Expect
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.Type as Type exposing (Definition(..), Type)
import Morphir.Scala.AST as Scala exposing (ArgValue(..), Generator(..), Lit(..), Pattern(..), Value(..))
import Morphir.Scala.Feature.Codec exposing (mapTypeDefinitionToEncoder, mapTypeToDecoderReference, mapTypeToEncoderReference)
import Test exposing (Test, describe, test)


mapTypeToEncoderReferenceTests : Test
mapTypeToEncoderReferenceTests =
    let
        positiveTest name tpeName tpePath typeParams tpe expectedOutput =
            test name
                (\_ ->
                    case mapTypeToEncoderReference tpeName tpePath typeParams tpe of
                        Ok output ->
                            output
                                |> Expect.equal expectedOutput

                        Err error ->
                            Expect.fail error
                )
    in
    describe "Generate Encoder Reference Tests"
        [ positiveTest "1. Type Variable "
            []
            []
            [ [] ]
            (Type.Variable () [ "foo" ])
            (Scala.Variable "encodeFoo")
        , positiveTest "2. Type Reference"
            []
            []
            [ [] ]
            (Type.Reference () (fqn "morphir" "sdk" "string") [])
            (Scala.Ref [ "morphir", "sdk", "Codec" ] "encodeString")
        , positiveTest
            "3. Type Record with two fields"
            []
            []
            [ [] ]
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
            []
            []
            [ [] ]
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


mapTypeToDecoderReferenceTests : Test
mapTypeToDecoderReferenceTests =
    let
        positiveTest name maybeTypeNameAndPath tpe expectedOutput =
            test name
                (\_ ->
                    case mapTypeToDecoderReference maybeTypeNameAndPath tpe of
                        Ok output ->
                            output
                                |> Expect.equal expectedOutput

                        Err error ->
                            Expect.fail error
                )
    in
    describe "Generate Decoder Reference Test"
        [ positiveTest "1. Type Variable "
            (Just ( [], [] ))
            (Type.Variable () [ "foo" ])
            (Scala.Variable "decodeFoo")
        , positiveTest "2. Type Reference"
            (Just ( [], [] ))
            (Type.Reference () (fqn "foo" "bar" "baz") [])
            (Scala.Ref [ "foo", "bar", "Codec" ] "decodeBaz")
        ]
