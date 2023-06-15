module Morphir.Scala.Feature.CodecTests exposing (..)

import Expect
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.Type as Type exposing (Definition(..), Type)
import Morphir.Scala.AST as Scala exposing (ArgValue(..), Generator(..), Lit(..), Pattern(..), Value(..))
import Morphir.Scala.Feature.Codec exposing (mapTypeToDecoderReference, mapTypeToEncoderReference)
import Test exposing (Test, describe, test)


mapTypeToEncoderReferenceTests : Test
mapTypeToEncoderReferenceTests =
    let
        positiveTest name maybeFqn tpeName tpePath typeParams tpe expectedOutput =
            test name
                (\_ ->
                    case mapTypeToEncoderReference maybeFqn tpeName tpePath typeParams tpe of
                        Ok output ->
                            output
                                |> Expect.equal expectedOutput

                        Err error ->
                            Expect.fail error
                )
    in
    describe "Generate Encoder Reference Tests"
        [ positiveTest "1. Type Variable "
            (Just ( [ [] ], [ [] ], [] ))
            []
            []
            [ [] ]
            (Type.Variable () [ "foo" ])
            (Scala.Variable "encodeFoo")
        , positiveTest "2. Type Reference"
            (Just ( [ [] ], [ [] ], [] ))
            []
            []
            [ [] ]
            (Type.Reference () (fqn "morphir" "sdk" "string") [])
            (Scala.Ref [ "morphir", "sdk", "Codec" ] "encodeString")
        , positiveTest
            "3. Type Record with two fields"
            (Just ( [ [] ], [ [] ], [] ))
            []
            []
            [ [] ]
            (Type.Record ()
                [ Type.Field [ "name" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "String") [])
                , Type.Field [ "age" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "Int") [])
                ]
            )
            (Scala.Lambda [ ( "", Just (Scala.TypeApply (Scala.TypeRef [ "", "" ] "") [ Scala.TypeVar "" ]) ) ]
                (Scala.Apply (Scala.Ref [ "io", "circe", "Json" ] "obj")
                    [ Scala.ArgValue Nothing
                        (Scala.Tuple
                            [ Scala.Literal (Scala.StringLit "name")
                            , Scala.Apply (Scala.Ref [ "morphir", "sdk", "basics", "Codec" ] "encodeString") [ Scala.ArgValue Nothing (Scala.Select (Scala.Variable "") "name") ]
                            ]
                        )
                    , Scala.ArgValue Nothing
                        (Scala.Tuple
                            [ Scala.Literal (Scala.StringLit "age")
                            , Scala.Apply (Scala.Ref [ "morphir", "sdk", "basics", "Codec" ] "encodeInt") [ Scala.ArgValue Nothing (Scala.Select (Scala.Variable "") "age") ]
                            ]
                        )
                    ]
                )
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
        , positiveTest "3. Type Record"
            (Just ( [], [] ))
            (Type.Record ()
                [ Type.Field [ "name" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "String") [])
                , Type.Field [ "age" ] (Type.Reference () (fqn "morphir.sdk" "Basics" "Int") [])
                ]
            )
            (Scala.Lambda [ ( "c", Just (Scala.TypeRef [ "io", "circe" ] "HCursor") ) ]
                (Scala.ForComp
                    [ Scala.Extract (Scala.NamedMatch "name_")
                        (Scala.Apply (Scala.Select (Scala.Apply (Scala.Select (Scala.Variable "c") "downField") [ Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit "name")) ]) "as")
                            [ Scala.ArgValue Nothing (Scala.Ref [ "morphir", "sdk", "basics", "Codec" ] "decodeString") ]
                        )
                    , Scala.Extract (Scala.NamedMatch "age_")
                        (Scala.Apply (Scala.Select (Scala.Apply (Scala.Select (Scala.Variable "c") "downField") [ Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit "age")) ]) "as")
                            [ Scala.ArgValue Nothing (Scala.Ref [ "morphir", "sdk", "basics", "Codec" ] "decodeInt") ]
                        )
                    ]
                    (Scala.Apply (Scala.Ref [] "") [ Scala.ArgValue Nothing (Scala.Variable "name_"), Scala.ArgValue Nothing (Scala.Variable "age_") ])
                )
            )
        , positiveTest "4. Tuple with 2 fields"
            (Just ( [], [] ))
            (Type.Tuple () [ Type.Reference () (fqn "morphir.sdk" "basics" "string") [], Type.Reference () (fqn "morphir.sdk" "basics" "int") [] ])
            (Scala.Lambda [ ( "c", Just (Scala.TypeRef [ "io", "circe" ] "HCursor") ) ]
                (Scala.ForComp
                    [ Scala.Extract (Scala.NamedMatch "arg1")
                        (Scala.Apply (Scala.Select (Scala.Apply (Scala.Select (Scala.Variable "c") "downN") [ Scala.ArgValue Nothing (Scala.Literal (Scala.IntegerLit 0)) ]) "as")
                            [ Scala.ArgValue Nothing (Scala.Ref [ "morphir", "sdk", "basics", "Codec" ] "decodeString") ]
                        )
                    , Scala.Extract (Scala.NamedMatch "arg2")
                        (Scala.Apply (Scala.Select (Scala.Apply (Scala.Select (Scala.Variable "c") "downN") [ Scala.ArgValue Nothing (Scala.Literal (Scala.IntegerLit 1)) ]) "as")
                            [ Scala.ArgValue Nothing (Scala.Ref [ "morphir", "sdk", "basics", "Codec" ] "decodeInt") ]
                        )
                    ]
                    (Scala.Tuple [ Scala.Variable "arg1", Scala.Variable "arg2" ])
                )
            )
        ]
