module TestLetDef exposing(..)

import CsvUtils exposing(..)
import Test exposing(Test)
import TestUtils exposing (executeTest)
import AntiqueSSDataSource exposing (antiqueSSDataSource)
import SparkTests.FunctionTests exposing (testLetDef)

testForLetDef : Test
testForLetDef =
      executeTest "testLetDef"  antiqueSSDataSource  testLetDef antiqueSSEncoder






