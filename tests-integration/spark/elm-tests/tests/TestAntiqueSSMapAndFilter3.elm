module TestAntiqueSSMapAndFilter3 exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForMapAndFilter3 : Test
testForMapAndFilter3 =
    executeTest "testMapAndFilter3" antiqueSSDataSource testMapAndFilter3 antiqueSSEncoder
