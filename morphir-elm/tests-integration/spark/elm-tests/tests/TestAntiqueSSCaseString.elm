module TestAntiqueSSCaseString exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForCaseString : Test
testForCaseString =
    executeTest "testCaseString" antiqueSSDataSource testCaseString antiqueSSEncoder
