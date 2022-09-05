module TestString exposing (..)

import CsvUtils exposing (..)
import FooStringDataSource exposing (fooStringDataSource)
import SparkTests.TypeTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForString : Test
testForString =
    executeTest "testString" fooStringDataSource testString fooStringEncoder
