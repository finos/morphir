module Morphir.Correctness.Test exposing (..)

import Dict exposing (Dict)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Value exposing (RawValue, Value(..))


type alias TestCase =
    { inputs : List (Maybe RawValue)
    , expectedOutput : RawValue
    , description : String
    }


type alias TestCases =
    List TestCase


type alias TestSuite =
    Dict FQName TestCases



-- URLs for Testing TestSuites
-- http://localhost:8000/function/Morphir.Reference.Model:Insight.UseCase1:limitTracking
-- http://localhost:8000/function/Morphir.Reference.Model:Issues.Issue410:addFunction
