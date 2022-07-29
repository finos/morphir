module TestAntiqueSSListMaximum exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForListMaximum : Test
testForListMaximum =
    executeTest "testListMaximum" antiqueSSDataSource testListMaximum fooFloatMaybeEncoder
