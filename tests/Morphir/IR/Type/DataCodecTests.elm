module Morphir.IR.Type.DataCodecTests exposing (decodeDataTest)

import Expect exposing (Expectation)
import Fuzz
import Json.Decode as Decode
import Morphir.IR as IR exposing (IR)
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.SDK.Basics exposing (boolType, floatType, intType)
import Morphir.IR.SDK.Char exposing (charType)
import Morphir.IR.SDK.List exposing (listType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Type.DataCodec exposing (decodeData, encodeData)
import Morphir.IR.Value as Value exposing (RawValue, Value)
import Morphir.IR.ValueFuzzer exposing (boolFuzzer, charFuzzer, floatFuzzer, intFuzzer, listFuzzer, stringFuzzer)
import Test exposing (Test, describe, fuzz, test)


ir : IR
ir =
    IR.empty


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
            Type.Tuple ()
                [ intType (), boolType (), floatType (), charType (), stringType () ]

        emptyTupleType : Type ()
        emptyTupleType =
            Type.Tuple () []

        intListType : Type ()
        intListType =
            Type.Reference () (fqn "Morphir.SDK" "List" "List") [ intType () ]

        mayBeType : Type ()
        mayBeType =
            Type.Reference () (fqn "Morphir.SDK" "Maybe" "Maybe") [ intType () ]
    in
    describe "JsonDecoderTest"
        [ fuzz boolFuzzer "Bool" (encodeDecodeTest (boolType ()))
        , fuzz intFuzzer "Int" (encodeDecodeTest (intType ()))
        , fuzz floatFuzzer "Float" (encodeDecodeTest (floatType ()))
        , fuzz charFuzzer "Char" (encodeDecodeTest (charType ()))
        , fuzz stringFuzzer "String" (encodeDecodeTest (stringType ()))
        , fuzz (listFuzzer stringFuzzer) "List String" (encodeDecodeTest (listType () (stringType ())))
        , fuzz (listFuzzer intFuzzer) "List Int" (encodeDecodeTest (listType () (intType ())))
        , fuzz (listFuzzer floatFuzzer) "List Float" (encodeDecodeTest (listType () (floatType ())))
        , test "RecordDecoder"
            (\_ ->
                case decodeData ir recordType of
                    Ok decoder ->
                        Expect.equal (Decode.decodeString decoder "{ \"foo\" : \"Hello\", \"bar\" : true, \"baz\" : 99, \"bee\" : 49.56, \"ball\" : \"c\" }")
                            (Ok
                                (Value.Record ()
                                    [ ( [ "foo" ], Value.Literal () (StringLiteral "Hello") )
                                    , ( [ "bar" ], Value.Literal () (BoolLiteral True) )
                                    , ( [ "baz" ], Value.Literal () (IntLiteral 99) )
                                    , ( [ "bee" ], Value.Literal () (FloatLiteral 49.56) )
                                    , ( [ "ball" ], Value.Literal () (CharLiteral 'c') )
                                    ]
                                )
                            )

                    Err error ->
                        Expect.equal "Cannot Decode this type" error
            )
        , test "EmptyRecordDecoder"
            (\_ ->
                case decodeData ir emptyRecordType of
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
                case decodeData ir emptyTupleType of
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


encodeDecodeTest : Type ta -> RawValue -> Expectation
encodeDecodeTest tpe value =
    Result.map2
        (\encode decoder ->
            encode value
                |> Decode.decodeValue decoder
                |> Expect.equal (Ok value)
        )
        (encodeData ir tpe)
        (decodeData ir tpe)
        |> Result.withDefault (Expect.fail ("Could not create codec for " ++ Debug.toString tpe))
