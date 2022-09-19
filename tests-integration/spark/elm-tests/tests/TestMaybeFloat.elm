module TestMaybeFloat exposing (..)

import CsvUtils exposing (..)
import FooMaybeFloatDataSource exposing (fooMaybeFloatDataSource)
import SparkTests.TypeTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForMaybeFloat : Test
testForMaybeFloat =
    executeTest "testMaybeFloat" fooMaybeFloatDataSource testMaybeFloat fooFloatMaybeEncoder
