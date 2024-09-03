module TestAntiqueSSWhere1 exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForWhere1 : Test
testForWhere1 =
    executeTest "testWhere1" antiqueSSDataSource testWhere1 antiqueSSEncoder
