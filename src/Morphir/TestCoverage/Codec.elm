module Morphir.TestCoverage.Codec exposing (..)

import AssocList as AssocDict
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.NodeId as NodeId
import Morphir.TestCoverage.Backend exposing (TestCoverageResult)


encodeTestCoverageResult : TestCoverageResult -> Encode.Value
encodeTestCoverageResult testCoverageResult =
    testCoverageResult
        |> AssocDict.toList
        |> List.map
            (\( nodeId, coverage ) ->
                ( NodeId.nodeIdToString nodeId
                , Encode.object
                    [ ( "numberOfBranches", Encode.int coverage.numberOfBranches )
                    , ( "numberOfCoveredBranches", Encode.int coverage.numberOfCoveredBranches )
                    ]
                )
            )
        |> Encode.object


encodeTestCoverageError : Decode.Error -> Encode.Value
encodeTestCoverageError err =
    case err of
        Decode.Field errMsg error ->
            Encode.list identity
                [ Encode.list identity [ Encode.string errMsg, error |> encodeTestCoverageError ]
                , Encode.null
                ]

        Decode.Index idx error ->
            Encode.list identity
                [ Encode.list identity [ Encode.int idx, error |> encodeTestCoverageError ]
                , Encode.null
                ]

        Decode.OneOf errors ->
            Encode.list identity
                [ Encode.list identity (errors |> List.map encodeTestCoverageError)
                , Encode.null
                ]

        Decode.Failure errMsg value ->
            Encode.list identity
                [ Encode.list identity [ Encode.string errMsg, Encode.string "Decode Failure" ]
                , Encode.null
                ]
