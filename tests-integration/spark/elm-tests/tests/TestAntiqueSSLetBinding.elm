module TestAntiqueSSLetBinding exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForLetBinding : Test
testForLetBinding =
    executeTest "testLetBinding" antiqueSSDataSource testLetBinding antiqueSSEncoder
