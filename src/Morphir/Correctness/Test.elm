module Morphir.Correctness.Test exposing (..)

import Dict exposing (Dict)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Value exposing (RawValue, Value(..))


type alias TestCase =
    { inputs : List RawValue
    , expectedOutput : RawValue
    , description : String
    }


type alias TestCases =
    List TestCase


type alias TestSuite =
    Dict FQName TestCases



-- http://localhost:8000/function/Morphir.Reference.Model:Insight.UseCase1:limitTracking
-- http://localhost:8000/function/Morphir.Reference.Model:Issues.Issue410:addFunction
-- Test suite will be Dictionary of function name + testcases attached with it
-- FQName is complete name of the function
-- Test case is basically record of input and expected output
-- Input is dictionary of argument name and value associated with it.
