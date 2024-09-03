module TestBool exposing (..)

import CsvUtils exposing (..)
import FooBoolDataSource exposing (fooBoolDataSource)
import SparkTests.TypeTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForBool : Test
testForBool =
    executeTest "testBool" fooBoolDataSource testBool fooBoolEncoder
