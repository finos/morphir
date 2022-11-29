module TestAntiqueSSMapAndFilter2 exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForMapAndFilter2 : Test
testForMapAndFilter2 =
    executeTest "testMapAndFilter2" antiqueSSDataSource testMapAndFilter2 antiqueSSEncoder
