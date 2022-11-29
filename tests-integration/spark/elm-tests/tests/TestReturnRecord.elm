module TestReturnRecord exposing (..)

import CsvUtils exposing (encodeMinSumRecord)
import AntiqueAgeDataSource exposing (antiqueAgeDataSource)
import SparkTests.ReturnTypeTests exposing (testReturnRecord)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForReturnListRecords : Test
testForReturnListRecords =
    executeTest "testReturnRecord" antiqueAgeDataSource testReturnRecord encodeMinSumRecord
