module TestReturnListRecords exposing (..)

import CsvUtils exposing (FooFloat, fooFloatEncoder)
import FooFloatDataSource exposing (fooFloatDataSource)
import SparkTests.ReturnTypeTests exposing (testReturnListRecords)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForReturnListRecords : Test
testForReturnListRecords =
    executeTest "testReturnListRecords" fooFloatDataSource testReturnListRecords fooFloatEncoder
