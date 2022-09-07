module TestAntiqueSSWhere3 exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForWhere3 : Test
testForWhere3 =
    executeTest "testWhere3" antiqueSSDataSource testWhere3 antiqueSSEncoder
