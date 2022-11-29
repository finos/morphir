module TestAntiqueSSSelect3 exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForSelect3 : Test
testForSelect3 =
    executeTest "testSelect3" antiqueSSDataSource testSelect3 antiqueAgeEncoder
