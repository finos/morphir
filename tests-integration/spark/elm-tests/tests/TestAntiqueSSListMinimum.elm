module TestAntiqueSSListMinimum exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForListMinimum : Test
testForListMinimum =
    executeTest "testListMinimum" antiqueSSDataSource testListMinimum fooFloatMaybeEncoder