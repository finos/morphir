module TestFloat exposing (..)

import CsvUtils exposing (..)
import FooFloatDataSource exposing (fooFloatDataSource)
import SparkTests.TypeTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForFloat : Test
testForFloat =
    executeTest "testFloat" fooFloatDataSource testFloat fooFloatEncoder
