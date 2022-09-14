module TestMaybeString exposing (..)

import CsvUtils exposing (..)
import FooMaybeStringDataSource exposing (fooMaybeStringDataSource)
import CsvUtils exposing (fooStringMaybeEncoder)
import SparkTests.TypeTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForMaybeString : Test
testForMaybeString =
    executeTest "testMaybeString" fooMaybeStringDataSource testMaybeString fooStringMaybeEncoder
