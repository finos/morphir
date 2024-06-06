module TestMaybeInt exposing (..)

import CsvUtils exposing (..)
import FooMaybeIntDataSource exposing (fooMaybeIntDataSource)
import SparkTests.TypeTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForMaybeInt : Test
testForMaybeInt =
    executeTest "testMaybeInt" fooMaybeIntDataSource testMaybeInt fooIntMaybeEncoder
