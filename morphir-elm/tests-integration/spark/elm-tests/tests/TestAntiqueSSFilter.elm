module TestAntiqueSSFilter exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForFilter : Test
testForFilter =
    executeTest "testFilter" antiqueSSDataSource testFilter antiqueSSEncoder
