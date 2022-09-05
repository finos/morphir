module TestCaseInt exposing (..)

import CsvUtils exposing (..)
import FooIntDataSource exposing (fooIntDataSource)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForCaseInt : Test
testForCaseInt =
    executeTest "testCaseInt" fooIntDataSource testCaseInt fooIntEncoder
