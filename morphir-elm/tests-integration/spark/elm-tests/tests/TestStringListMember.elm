module TestStringListMember exposing (..)

import AntiqueNameDataSource exposing (antiqueNameDataSource)
import CsvUtils exposing (..)
import SparkTests.ListMemberTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForStringListMember : Test
testForStringListMember =
    executeTest "testStringListMember" antiqueNameDataSource testStringListMember antiqueNameEncoder
