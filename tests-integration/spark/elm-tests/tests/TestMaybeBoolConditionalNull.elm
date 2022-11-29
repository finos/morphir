module TestMaybeBoolConditionalNull exposing (..)

import CsvUtils exposing (..)
import FooMaybeBoolDataSource exposing (fooMaybeBoolDataSource)
import SparkTests.TypeTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForMaybeBoolConditionalNull : Test
testForMaybeBoolConditionalNull =
    executeTest "testMaybeBoolConditionalNull" fooMaybeBoolDataSource testMaybeBoolConditionalNull fooBoolMaybeEncoder
