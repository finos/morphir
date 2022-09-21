module TestAntiqueSSCaseEnum exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForCaseEnum : Test
testForCaseEnum =
    executeTest "testCaseEnum" antiqueSSDataSource testCaseEnum antiqueSSEncoder
