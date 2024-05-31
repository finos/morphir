module TestMaybeBoolConditionalNotNull exposing (..)

import CsvUtils exposing (..)
import FooMaybeBoolDataSource exposing (fooMaybeBoolDataSource)
import SparkTests.TypeTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForMaybeBoolConditionalNotNull : Test
testForMaybeBoolConditionalNotNull =
    executeTest "testMaybeBoolConditionalNotNull" fooMaybeBoolDataSource testMaybeBoolConditionalNotNull fooBoolMaybeEncoder
