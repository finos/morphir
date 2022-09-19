module TestAntiqueSSFrom exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForFrom : Test
testForFrom =
    executeTest "testFrom" antiqueSSDataSource testFrom antiqueSSEncoder
