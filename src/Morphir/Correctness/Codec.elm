module Morphir.Correctness.Codec exposing (..)

import Dict
import Json.Decode as Decode exposing (string)
import Json.Encode as Encode
import Morphir.Correctness.Test exposing (TestCase, TestCases, TestSuite)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.FQName.CodecV1 as FQName exposing (decodeFQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Type.DataCodec as DataCodec
import Morphir.IR.Value as Value exposing (RawValue)
import Morphir.SDK.ResultList as ListOfResults


encodeTestSuite : Distribution -> TestSuite -> Result String Encode.Value
encodeTestSuite ir testSuite =
    testSuite
        |> Dict.toList
        |> List.map
            (\( fQName, testCases ) ->
                case Distribution.lookupValueSpecification fQName ir of
                    Just valueSpec ->
                        testCases
                            |> encodeTestCases ir valueSpec
                            |> Result.map
                                (\encodedList ->
                                    Encode.list identity
                                        [ FQName.encodeFQName fQName
                                        , encodedList
                                        ]
                                )

                    Nothing ->
                        Err "Cannot find function in IR"
            )
        |> ListOfResults.keepFirstError
        |> Result.map (Encode.list identity)


decodeTestSuite : Distribution -> Decode.Decoder TestSuite
decodeTestSuite ir =
    Decode.map Dict.fromList
        (Decode.list
            (Decode.index 0 decodeFQName
                |> Decode.andThen
                    (\fQName ->
                        case Distribution.lookupValueSpecification fQName ir of
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


encodeTestCases : Distribution -> Value.Specification () -> TestCases -> Result String Encode.Value
encodeTestCases ir valueSpec testCases =
    let
        encodeInput : List ( Name, Type () ) -> TestCase -> Result String Encode.Value
        encodeInput inputTypes testCase =
            List.map2
                (\( _, tpe ) maybeTestCaseInput ->
                    DataCodec.encodeData ir tpe
                        |> Result.andThen
                            (\encoder ->
                                case maybeTestCaseInput of
                                    Just testCaseInput ->
                                        testCaseInput |> encoder

                                    Nothing ->
                                        Ok Encode.null
                            )
                )
                inputTypes
                testCase.inputs
                |> ListOfResults.keepFirstError
                |> Result.map (Encode.list identity)
    in
    testCases
        |> List.map
            (\testCase ->
                let
                    ( inputEncoder, outputEncoder ) =
                        ( encodeInput
                            valueSpec.inputs
                            testCase
                        , DataCodec.encodeData ir valueSpec.output
                            |> Result.andThen
                                (\encoder ->
                                    testCase.expectedOutput |> encoder
                                )
                        )
                in
                Result.map2
                    (\inpEncoder outEncoder ->
                        Encode.object
                            [ ( "inputs", inpEncoder )
                            , ( "expectedOutput", outEncoder )
                            , ( "description", testCase.description |> Encode.string )
                            ]
                    )
                    inputEncoder
                    outputEncoder
            )
        |> ListOfResults.keepFirstError
        |> Result.map (Encode.list identity)


decodeTestCase : Distribution -> Value.Specification () -> Decode.Decoder TestCase
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
    Decode.map3 Morphir.Correctness.Test.TestCase
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
                                                    List.append inputsSoFar [ Just input ]
                                                )
                                        )
                                )
                        )
                    )
                    ( 0, Decode.succeed [] )
                |> Tuple.second
            )
        )
        (Decode.field "expectedOutput" (DataCodec.decodeData ir valueSpec.output |> resultToFailure))
        (Decode.field "description" string)
