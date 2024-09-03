module TestReturnInlineApplyRecord exposing (..)

import CsvUtils exposing (encodeMinSumRecord)
import AntiqueAgeDataSource exposing (antiqueAgeDataSource)
import SparkTests.ReturnTypeTests exposing (testReturnInlineApplyRecord)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForReturnListRecords : Test
testForReturnListRecords =
    executeTest "testReturnInlineApplyRecord" antiqueAgeDataSource testReturnInlineApplyRecord encodeMinSumRecord
