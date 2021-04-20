module Morphir.Correctness.Codec exposing (..)

import Dict
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.Correctness.Test exposing (TestCase, TestCases, TestSuite)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.FQName.Codec as FQName exposing (decodeFQName)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Type.DataCodec as DataCodec
import Morphir.IR.Value as Value



--
--encodeTestSuite : IR -> TestSuite -> Encode.Value
--encodeTestSuite ir testSuite =
--    testSuite
--        |> Dict.toList
--        |> Encode.list
--            (\( fQName, testCases ) ->
--                case IR.lookupValueSpecification fQName ir of
--                    Just valueSpec ->
--                        Encode.list identity
--                            [ FQName.encodeFQName fQName
--                            , encodeTestCases ir valueSpec testCases
--                            ]
--
--                    Nothing ->
--                        --TODO
--            )


decodeVersionedTestSuite : IR -> Decode.Decoder TestSuite
decodeVersionedTestSuite ir =
    Decode.field "TestCases" (decodeTestSuite ir)


decodeTestSuite : IR -> Decode.Decoder TestSuite
decodeTestSuite ir =
    Decode.map Dict.fromList
        (Decode.list
            (Decode.index 0 decodeFQName
                |> Decode.andThen
                    (\fQName ->
                        case IR.lookupValueSpecification fQName ir of
                            Just valueSpec ->
                                Decode.index 1
                                    (Decode.list (decodeTestCase ir valueSpec)
                                        |> Decode.map (Tuple.pair fQName)
                                    )

                            Nothing ->
                                Decode.fail ("Cannot find " ++ FQName.toString fQName)
                    )
            )
        )



--encodeTestCases : IR -> Value.Specification () -> TestCases -> Encode.Value
--encodeTestCases ir valueSpec testCases =
--    let
--        result = "TODO"
--        --resultToFailure : Result String (Decode.Decoder a) -> Decode.Decoder a
--        --resultToFailure result =
--        --    case result of
--        --        Ok decoder ->
--        --            decoder
--        --
--        --        Err error ->
--        --            Decode.fail error
--
--    in
--    testCases
--        |> Encode.list
--            (\testCase ->
--                Encode.object
--                    [
--                    ( "inputs", DataCodec.encodeData ir
--                    (valueSpec.inputs
--                    |> List.map (\( _, tpe ) -> tpe)
--                    |> Type.Tuple ()))
--                    , ( "expectedOutput", DataCodec.encodeData ir valueSpec.output  )
--                    ]
--            )


decodeTestCase : IR -> Value.Specification () -> Decode.Decoder TestCase
decodeTestCase ir valueSpec =
    let
        resultToFailure : Result String (Decode.Decoder a) -> Decode.Decoder a
        resultToFailure result =
            case result of
                Ok decoder ->
                    decoder

                Err error ->
                    Decode.fail error
    in
    Decode.map2 Morphir.Correctness.Test.TestCase
        (Decode.field "inputs"
            (valueSpec.inputs
                |> List.foldl
                    (\( argName, argType ) ( index, decoderSoFar ) ->
                        ( index + 1
                        , decoderSoFar
                            |> Decode.andThen
                                (\inputsSoFar ->
                                    Decode.index index
                                        (DataCodec.decodeData ir argType
                                            |> resultToFailure
                                            |> Decode.map
                                                (\input ->
                                                    inputsSoFar |> Dict.insert argName input
                                                )
                                        )
                                )
                        )
                    )
                    ( 0, Decode.succeed Dict.empty )
                |> Tuple.second
            )
        )
        (Decode.field "expectedOutput" (DataCodec.decodeData ir valueSpec.output |> resultToFailure))
