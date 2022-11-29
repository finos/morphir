module TestAntiqueSSListSum exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForListSum : Test
testForListSum =
    executeTest "testListSum" antiqueSSDataSource testListSum fooFloatEncoder