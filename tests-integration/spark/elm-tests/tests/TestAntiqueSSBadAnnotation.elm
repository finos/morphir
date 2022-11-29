module TestAntiqueSSBadAnnotation exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForBadAnnotation : Test
testForBadAnnotation =
    executeTest "testBadAnnotation" antiqueSSDataSource testBadAnnotation encodeProductList
