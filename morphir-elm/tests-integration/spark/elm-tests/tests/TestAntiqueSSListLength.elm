module TestAntiqueSSListLength exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForListLength : Test
testForListLength =
    executeTest "testListLength" antiqueSSDataSource testListLength fooIntEncoder