module TestInt exposing (..)

import CsvUtils exposing (..)
import FooIntDataSource exposing (fooIntDataSource)
import SparkTests.TypeTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForInt : Test
testForInt =
    executeTest "testInt" fooIntDataSource testInt fooIntEncoder
