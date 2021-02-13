module Morphir.IR.JsonDecoderTest exposing (decodeDataTest)

import Expect exposing (Expectation)
import Json.Decode as Decode
import Morphir.IR.DataCodec exposing (decodeData, encodeData)
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.SDK.Basics exposing (boolType, floatType, intType)
import Morphir.IR.SDK.Char exposing (charType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type as Type exposing (ResolvedType, Type)
import Morphir.IR.Value as Value exposing (RawValue, Value)
import Morphir.IR.ValueFuzzer exposing (floatFuzzer, intFuzzer)
import Test exposing (Test, describe, fuzz, test)


decodeDataTest : Test
decodeDataTest =
    let
        recordType : ResolvedType
        recordType =
            Type.Record Nothing
                [ Type.Field [ "foo" ] (stringType Nothing)
                , Type.Field [ "bar" ] (boolType Nothing)
                , Type.Field [ "baz" ] (intType Nothing)
                , Type.Field [ "bee" ] (floatType Nothing)
                , Type.Field [ "ball" ] (charType Nothing)
                ]

        emptyRecordType : ResolvedType
        emptyRecordType =
            Type.Record Nothing []

        tupleType : ResolvedType
        tupleType =
            Type.Tuple Nothing
                [ intType Nothing, boolType Nothing, floatType Nothing, charType Nothing, stringType Nothing ]

        emptyTupleType : ResolvedType
        emptyTupleType =
            Type.Tuple Nothing []

        intListType : ResolvedType
        intListType =
            Type.Reference Nothing (fqn "Morphir.SDK" "List" "List") [ intType Nothing ]

        mayBeType : Type ()
        mayBeType =
            Type.Reference () (fqn "Morphir.SDK" "Maybe" "Maybe") [ intType () ]
    in
    describe "JsonDecoderTest"
        [ test "BoolDecoder"
            (\_ ->
                case decodeData (boolType Nothing) of
                    Ok decoder ->
                        Expect.equal (Decode.decodeString decoder "true") (Ok (Value.literal () (BoolLiteral True)))

                    Err error ->
                        Expect.equal "Cannot Decode this type" error
            )
        , fuzz intFuzzer "Int" (encodeDecodeTest (intType Nothing))
        , fuzz floatFuzzer "Float" (encodeDecodeTest (floatType Nothing))
        , test "CharDecoder"
            (\_ ->
                case decodeData (charType Nothing) of
                    Ok decoder ->
                        Expect.equal (Decode.decodeString decoder "\"a\"") (Ok (Value.literal () (StringLiteral "a")))

                    Err error ->
                        Expect.equal "Cannot Decode this type" error
            )
        , test "StringDecoder"
            (\_ ->
                case decodeData (stringType Nothing) of
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
        , test "IntListDecoder"
            (\_ ->
                case decodeData intListType of
                    Ok decoder ->
                        Expect.equal (Decode.decodeString decoder "[]") (Ok (Value.List () []))

                    Err error ->
                        Expect.fail error
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


encodeDecodeTest : ResolvedType -> RawValue -> Expectation
encodeDecodeTest tpe value =
    Result.map2
        (\encode decoder ->
            encode value
                |> Decode.decodeValue decoder
                |> Expect.equal (Ok value)
        )
        (encodeData tpe)
        (decodeData tpe)
        |> Result.withDefault (Expect.fail ("Could not create codec for " ++ Debug.toString tpe))
