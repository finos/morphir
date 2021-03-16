module Morphir.IR.Type.DataCodecTests exposing (decodeDataTest)

import Expect exposing (Expectation)
import Json.Decode as Decode
import Morphir.IR as IR exposing (IR)
import Morphir.IR.SDK.Basics exposing (boolType, floatType, intType)
import Morphir.IR.SDK.Char exposing (charType)
import Morphir.IR.SDK.List exposing (listType)
import Morphir.IR.SDK.Maybe exposing (maybeType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Type.DataCodec exposing (decodeData, encodeData)
import Morphir.IR.ValueFuzzer as ValueFuzzer
import Test exposing (Test, describe, fuzz)


ir : IR
ir =
    IR.empty


decodeDataTest : Test
decodeDataTest =
    describe "JsonDecoderTest"
        [ encodeDecodeTest (boolType ())
        , encodeDecodeTest (intType ())
        , encodeDecodeTest (floatType ())
        , encodeDecodeTest (charType ())
        , encodeDecodeTest (stringType ())
        , encodeDecodeTest (listType () (stringType ()))
        , encodeDecodeTest (listType () (intType ()))
        , encodeDecodeTest (listType () (floatType ()))
        , encodeDecodeTest (maybeType () (floatType ()))
        , encodeDecodeTest (Type.Record () [])
        , encodeDecodeTest (Type.Record () [ Type.Field [ "foo" ] (intType ()) ])
        , encodeDecodeTest (Type.Record () [ Type.Field [ "foo" ] (intType ()), Type.Field [ "bar" ] (boolType ()) ])
        , encodeDecodeTest (Type.Tuple () [])
        , encodeDecodeTest (Type.Tuple () [ intType () ])
        , encodeDecodeTest (Type.Tuple () [ intType (), boolType () ])
        ]


encodeDecodeTest : Type () -> Test
encodeDecodeTest tpe =
    fuzz (ValueFuzzer.fromType ir tpe)
        (Debug.toString tpe)
        (\value ->
            Result.map2
                (\encode decoder ->
                    encode value
                        |> Result.andThen (Decode.decodeValue decoder >> Result.mapError Decode.errorToString)
                        |> Expect.equal (Ok value)
                )
                (encodeData ir tpe)
                (decodeData ir tpe)
                |> Result.withDefault (Expect.fail ("Could not create codec for " ++ Debug.toString tpe))
        )
