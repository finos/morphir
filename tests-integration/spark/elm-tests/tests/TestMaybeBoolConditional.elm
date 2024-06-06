module TestMaybeBoolConditional exposing (..)

import CsvUtils exposing (..)
import FooMaybeBoolDataSource exposing (fooMaybeBoolDataSource)
import SparkTests.TypeTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForMaybeBoolConditional : Test
testForMaybeBoolConditional =
    executeTest "testMaybeBoolConditional" fooMaybeBoolDataSource testMaybeBoolConditional fooBoolMaybeEncoder
