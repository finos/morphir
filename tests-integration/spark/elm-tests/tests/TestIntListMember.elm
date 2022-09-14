module TestIntListMember exposing (..)

import AntiqueAgeDataSource exposing (antiqueAgeDataSource)
import CsvUtils exposing (..)
import SparkTests.ListMemberTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForAgeListMember : Test
testForAgeListMember =
    executeTest "testIntListMember" antiqueAgeDataSource testIntListMember antiqueAgeEncoder
