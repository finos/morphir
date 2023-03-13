module Morphir.TestCoverage.Backend exposing (TestCoverageResult, getBranchCoverage)

import AssocList as AssocDict
import Dict exposing (Dict)
import Json.Encode as Encode
import Morphir.Correctness.BranchCoverage as BranchCoverage exposing (..)
import Morphir.Correctness.Test exposing (TestCase, TestSuite)
import Morphir.IR as IR exposing (..)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.NodeId as NodeId exposing (..)
import Morphir.IR.Package exposing (PackageName)
import Morphir.IR.Value as Value


type alias Coverage =
    { numberOfBranches : Int
    , numberOfCoveredBranches : Int
    }


type alias TestCoverageResult =
    AssocDict.Dict NodeID Coverage


{-| This method filters out branches without testcases and returns the total count of filtered
-}
calculateNumberOfCoveredBranches : List ( Branch ta va, List TestCase ) -> Int
calculateNumberOfCoveredBranches branchCoverageResult =
    branchCoverageResult
        |> List.filter
            (\item ->
                not (item |> Tuple.second |> List.isEmpty)
            )
        |> List.length


{-| This method loops through all values in a model and
-}
getBranchCoverage : ( PackageName, ModuleName ) -> IR -> TestSuite -> Module.Definition ta va -> TestCoverageResult
getBranchCoverage ( packageName, moduleName ) ir testSuite moduleDef =
    moduleDef.values
        |> Dict.toList
        |> List.map
            (\( valueName, accesscontrolledValueDef ) ->
                let
                    currentFQN =
                        FQName.fQName packageName moduleName valueName

                    valueTestCases =
                        testSuite
                            |> Dict.get currentFQN
                            |> Maybe.withDefault []

                    valueDef =
                        accesscontrolledValueDef.value.value
                in
                ( currentFQN |> ValueID
                , valueTestCases
                    |> BranchCoverage.assignTestCasesToBranches ir valueDef
                    |> (\lstOfBranchAndCoveredTestCases ->
                            { numberOfBranches = lstOfBranchAndCoveredTestCases |> List.length
                            , numberOfCoveredBranches = calculateNumberOfCoveredBranches lstOfBranchAndCoveredTestCases
                            }
                       )
                )
            )
        |> AssocDict.fromList
