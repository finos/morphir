module TestAntiqueSSFilter2 exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForFilter2 : Test
testForFilter2 =
    executeTest "testFilter2" antiqueSSDataSource testFilter2 antiqueSSEncoder
