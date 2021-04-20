module Morphir.Correctness.Test exposing (..)

import Dict exposing (Dict)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Value exposing (RawValue, Value(..))


type alias TestCase =
    { inputs : Dict Name RawValue
    , expectedOutput : RawValue
    }


type alias TestCases =
    List TestCase


type alias TestSuite =
    Dict FQName TestCases



-- Test suite will be Dictionary of function name + testcases attached with it
-- FQName is complete name of the function
-- Test case is basically record of input and expected output
-- Input is dictionary of argument name and value associated with it.
