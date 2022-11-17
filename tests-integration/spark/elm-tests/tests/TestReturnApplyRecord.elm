module TestReturnApplyRecord exposing (..)

import CsvUtils exposing (encodeMinSumRecord)
import AntiqueAgeDataSource exposing (antiqueAgeDataSource)
import SparkTests.ReturnTypeTests exposing (testReturnApplyRecord)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForReturnListRecords : Test
testForReturnListRecords =
    executeTest "testReturnApplyRecord" antiqueAgeDataSource testReturnApplyRecord encodeMinSumRecord
