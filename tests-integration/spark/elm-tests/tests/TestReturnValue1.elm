module TestReturnValue1 exposing (..)

import CsvUtils exposing (FooFloat)
import FooFloatDataSource exposing (fooFloatDataSource)
import SparkTests.ReturnTypeTests exposing (testReturnValue1)
import Test exposing (Test)
import TestUtils exposing (executeTest)


encodeResult : Float -> String
encodeResult result =
    "foo\u{000D}\n" ++ String.fromFloat result


testForReturnListRecords : Test
testForReturnListRecords =
    executeTest "testReturnValue1" fooFloatDataSource testReturnValue1 encodeResult
