module TestAntiqueSSSelect4 exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForSelect4 : Test
testForSelect4 =
    executeTest "testSelect4" antiqueSSDataSource testSelect4 encodeFloatList
