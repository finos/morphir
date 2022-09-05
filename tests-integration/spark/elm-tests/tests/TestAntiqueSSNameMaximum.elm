module TestAntiqueSSNameMaximum exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForNameMaximum : Test
testForNameMaximum =
    executeTest "testNameMaximum" antiqueSSDataSource testNameMaximum fooStringMaybeEncoder