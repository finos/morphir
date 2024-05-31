module TestAntiqueSSMapAndFilter exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForMapAndFilter : Test
testForMapAndFilter =
    executeTest "testMapAndFilter" antiqueSSDataSource testMapAndFilter antiqueSSEncoder
