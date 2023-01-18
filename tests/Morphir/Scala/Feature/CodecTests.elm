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
            (Scala.Lambda
                [ ( ""
                  , Just
                        (Scala.StructuralType
                            [ Scala.FunctionDecl { args = [], body = Nothing, modifiers = [], name = "name", returnType = Just (Scala.TypeRef [ "morphir", "sdk", "Basics" ] "String"), typeArgs = [] }
                            , Scala.FunctionDecl { args = [], body = Nothing, modifiers = [], name = "age", returnType = Just (Scala.TypeRef [ "morphir", "sdk", "Basics" ] "Int"), typeArgs = [] }
                            ]
                        )
                  )
                ]
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
            (Type.Tuple () [ Type.Reference () (fqn "morphir.sdk" "basics" "string") [] ])
            (Scala.Apply
                (Scala.Ref [ "morphir", "sdk", "tuple", "Codec" ] "decodeTuple")
                [ Scala.ArgValue Nothing (Scala.Ref [ "morphir", "sdk", "basics", "Codec" ] "decodeString") ]
            )
        ]
