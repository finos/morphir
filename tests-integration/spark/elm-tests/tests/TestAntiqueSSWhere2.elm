module TestAntiqueSSWhere2 exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForWhere2 : Test
testForWhere2 =
    executeTest "testWhere2" antiqueSSDataSource testWhere2 antiqueSSEncoder
