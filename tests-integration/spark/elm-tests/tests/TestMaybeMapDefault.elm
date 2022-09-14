module TestMaybeMapDefault exposing (..)

import CsvUtils exposing (..)
import FooMaybeBoolDataSource exposing (fooMaybeBoolDataSource)
import SparkTests.TypeTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


testForMaybeMapDefault : Test
testForMaybeMapDefault =
    executeTest "testMaybeMapDefault" fooMaybeBoolDataSource testMaybeMapDefault fooBoolMaybeEncoder
