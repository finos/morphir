module TestReturnMaybe exposing (..)

import CsvUtils exposing (FooFloat)
import FooFloatDataSource exposing (fooFloatDataSource)
import SparkTests.ReturnTypeTests exposing (testReturnMaybe)
import Test exposing (Test)
import TestUtils exposing (executeTest)


encodeResult : Maybe Float -> String
encodeResult result =
    result
        |> Maybe.map String.fromFloat
        |> Maybe.withDefault ""
        |> (++) "foo\u{000D}\n"


testForReturnListRecords : Test
testForReturnListRecords =
    executeTest "testReturnMaybe" fooFloatDataSource testReturnMaybe encodeResult
