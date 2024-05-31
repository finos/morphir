module TestEnum exposing (..)

import AntiqueProductDataSource exposing (antiqueProductDataSource)
import CsvUtils exposing (..)
import SparkTests.TypeTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForEnum : Test
testForEnum =
    executeTest "testEnum" antiqueProductDataSource testEnum antiqueProductEncoder
