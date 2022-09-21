module TestEnumListMember exposing (..)

import AntiqueProductDataSource exposing (antiqueProductDataSource)
import CsvUtils exposing (..)
import SparkTests.ListMemberTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForEnumListMember : Test
testForEnumListMember =
    executeTest "testEnumListMember" antiqueProductDataSource testEnumListMember antiqueProductEncoder
