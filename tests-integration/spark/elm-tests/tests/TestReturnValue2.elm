module TestReturnValue2 exposing (..)

import CsvUtils exposing (FooFloat)
import FooFloatDataSource exposing (fooFloatDataSource)
import SparkTests.ReturnTypeTests exposing (testReturnValue2)
import Test exposing (Test)
import TestUtils exposing (executeTest)


encodeResult : Int -> String
encodeResult result =
    "foo\u{000D}\n" ++ String.fromInt result


testForReturnListRecords : Test
testForReturnListRecords =
    executeTest "testReturnValue2" fooFloatDataSource testReturnValue2 encodeResult
