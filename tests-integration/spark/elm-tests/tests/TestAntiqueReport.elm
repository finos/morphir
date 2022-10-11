module TestAntiqueReport exposing (..)

import AntiquesDataSource exposing (antiquesDataSource)
import CsvUtils exposing (..)
import SparkTests.Rules.Income.Antique exposing (report)
import Test exposing (Test)
import TestUtils exposing (executeTest)

encodeResult : {antiqueValue : Float, seizedValue : Float, vintageValue : Float } -> String
encodeResult result =
    "antiqueValue,seizedValue,vintageValue\r\n"
        ++ ( String.fromFloat result.antiqueValue ) ++ ","
        ++ ( String.fromFloat result.seizedValue ) ++ ","
        ++ ( String.fromFloat result.vintageValue )

testForListSum : Test
testForListSum =
    executeTest "testAntiqueReport" antiquesDataSource report encodeResult
