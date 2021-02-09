module Morphir.IR.JsonDecoderTest exposing (..)

import Expect
import Json.Decode as Decode
import Morphir.IR.DataCodec exposing (decodeData)
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.SDK.Basics exposing (boolType, floatType, intType)
import Morphir.IR.SDK.Char exposing (charType)
import Morphir.IR.SDK.List exposing (listType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Test exposing (Test, describe, test)


decodeDataTest : Test
decodeDataTest =
    let
        recordType : Type ()
        recordType =
            Type.Record ()
                [ Type.Field [ "foo" ] (stringType ())
                , Type.Field [ "bar" ] (boolType ())
                , Type.Field [ "baz" ] (intType ())
                , Type.Field [ "bee" ] (floatType ())
                , Type.Field [ "ball" ] (charType ())
                ]

        emptyRecordType : Type ()
        emptyRecordType =
            Type.Record () []

        tupleType : Type ()
        tupleType =
            Type.Tuple () [ intType (), boolType (), floatType (), charType (), stringType () ]

        emptyTupleType : Type ()
        emptyTupleType =
            Type.Tuple () []

        emptyListType : Type ()
        emptyListType =
            Type.Reference () (fqn "Morphir.SDK" "List" "List") []

        mayBeType : Type ()
        mayBeType =
            Type.Reference () (fqn "Morphir.SDK" "Maybe" "Maybe") [ intType () ]
    in
    describe "JsonDecoderTest"
        [ test "BoolDecoder"
            (\_ ->
                case decodeData (boolType ()) of
                    Ok decoder ->
                        Expect.equal (Decode.decodeString decoder "true") (Ok (Value.literal () (BoolLiteral True)))

                    Err error ->
                        Expect.equal "Cannot Decode this type" error
            )
        , test "IntDecoder"
            (\_ ->
                case decodeData (intType ()) of
                    Ok decoder ->
                        Expect.equal (Decode.decodeString decoder "42") (Ok (Value.literal () (IntLiteral 42)))

                    Err error ->
                        Expect.equal "Cannot Decode this type" error
            )
        , test "FloatDecoder"
            (\_ ->
                case decodeData (floatType ()) of
                    Ok decoder ->
                        Expect.equal (Decode.decodeString decoder "42.5") (Ok (Value.literal () (FloatLiteral 42.5)))

                    Err error ->
                        Expect.equal "Cannot Decode this type" error
            )
        , test "CharDecoder"
            (\_ ->
                case decodeData (charType ()) of
                    Ok decoder ->
                        Expect.equal (Decode.decodeString decoder "\"a\"") (Ok (Value.literal () (StringLiteral "a")))

                    Err error ->
                        Expect.equal "Cannot Decode this type" error
            )
        , test "StringDecoder"
            (\_ ->
                case decodeData (stringType ()) of
                    Ok decoder ->
                        Expect.equal (Decode.decodeString decoder "\"Hello\"") (Ok (Value.literal () (StringLiteral "Hello")))

                    Err error ->
                        Expect.equal "Cannot Decode this type" error
            )

        --, test "ListDecoder"
        --    (\_ ->
        --        case decodeData (listType () (floatType ())) of
        --            Ok decoder ->
        --                Expect.equal (Decode.decodeString decoder "[1.1,2.3,3.5]")
        --                    (Ok
        --                        (Value.List ()
        --                            [ Value.Literal () (FloatLiteral 1.1)
        --                            , Value.Literal () (FloatLiteral 2.3)
        --                            , Value.Literal () (FloatLiteral 3.5)
        --                            ]
        --                        )
        --                    )
        --
        --            Err error ->
        --                Expect.equal "Cannot Decode this type" error
        --    )
        , test "EmptyListDecoder"
            (\_ ->
                case decodeData emptyListType of
                    Ok decoder ->
                        Expect.equal (Decode.decodeString decoder "[]") (Ok (Value.List () []))

                    Err error ->
                        Expect.equal "Cannot Decode this type" error
            )
        , test "RecordDecoder"
            (\_ ->
                case decodeData recordType of
                    Ok decoder ->
                        Expect.equal (Decode.decodeString decoder "{ \"foo\" : \"Hello\", \"bar\" : true, \"baz\" : 99, \"bee\" : 49.56, \"ball\" : \"c\" }")
                            (Ok
                                (Value.Record ()
                                    [ ( [ "foo" ], Value.Literal () (StringLiteral "Hello") )
                                    , ( [ "bar" ], Value.Literal () (BoolLiteral True) )
                                    , ( [ "baz" ], Value.Literal () (IntLiteral 99) )
                                    , ( [ "bee" ], Value.Literal () (FloatLiteral 49.56) )
                                    , ( [ "ball" ], Value.Literal () (StringLiteral "c") )
                                    ]
                                )
                            )

                    Err error ->
                        Expect.equal "Cannot Decode this type" error
            )
        , test "EmptyRecordDecoder"
            (\_ ->
                case decodeData emptyRecordType of
                    Ok decoder ->
                        Expect.equal (Decode.decodeString decoder "{}")
                            (Ok
                                (Value.Record ()
                                    []
                                )
                            )

                    Err error ->
                        Expect.equal "Cannot Decode this type" error
            )

        --, test "TupleDecoder"
        --    (\_ ->
        --        case decodeData tupleType of
        --            Ok decoder ->
        --                Expect.equal (Decode.decodeString decoder "[13,false,24.6,\"b\",\"tuple\"]")
        --                    (Ok
        --                        (Value.Tuple ()
        --                            [ Value.Literal () (IntLiteral 13)
        --                            , Value.Literal () (BoolLiteral False)
        --                            , Value.Literal () (FloatLiteral 24.6)
        --                            , Value.Literal () (StringLiteral "b")
        --                            , Value.Literal () (StringLiteral "tuple")
        --                            ]
        --                        )
        --                    )
        --
        --            Err error ->
        --                Expect.equal "Cannot Decode this type" error
        --    )
        , test "EmptyTupleDecoder"
            (\_ ->
                case decodeData emptyTupleType of
                    Ok decoder ->
                        Expect.equal (Decode.decodeString decoder "[]")
                            (Ok
                                (Value.Tuple ()
                                    []
                                )
                            )

                    Err error ->
                        Expect.equal "Cannot Decode this type" error
            )

        --, test "MaybeDecoderForNothing"
        --    (\_ ->
        --        case decodeData mayBeType of
        --            Ok decoder ->
        --                Expect.equal (Decode.decodeString decoder "null")
        --                    (Ok
        --                        (Value.Constructor () (fqn "Morphir.SDK" "Maybe" "Nothing"))
        --                    )
        --
        --            Err error ->
        --                Expect.equal "Cannot Decode this type" error
        --    )
        --, test "MaybeDecoderForJust"
        --    (\_ ->
        --        case decodeData mayBeType of
        --            Ok decoder ->
        --                Expect.equal (Decode.decodeString decoder "13")
        --                    (Ok
        --                        (Value.Apply ()
        --                            (Value.Constructor () (fqn "Morphir.SDK" "Maybe" "Just"))
        --                            (Value.Literal () (IntLiteral 13))
        --                        )
        --                    )
        --
        --            Err error ->
        --                Expect.equal "Cannot Decode this type" error
        --    )
        ]
