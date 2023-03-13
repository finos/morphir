module Morphir.TestCoverage.Codec exposing (..)

import AssocList as AssocDict
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
