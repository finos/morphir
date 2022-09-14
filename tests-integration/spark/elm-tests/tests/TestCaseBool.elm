module TestCaseBool exposing (..)

import CsvUtils exposing (..)
import FooBoolDataSource exposing (fooBoolDataSource)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForCaseBool : Test
testForCaseBool =
    executeTest "testCaseBool" fooBoolDataSource testCaseBool  fooBoolEncoder
