module GenerateFooFloatData exposing (..)

import Expect exposing (Expectation)
import GenerateAntiquesData exposing (..)
import Test exposing (..)


columnNameFloat : String
columnNameFloat =
    "foo"


generateFloat : List String -> List String
generateFloat =
    generator [ "9.99", "8.13", "4.675432", "347484.888", "12314252.99", "134890.0", "0.0", "444.00000", "7837539.23" ]


testFooFloatGeneration : Test
testFooFloatGeneration =
    let
        dataGenerateFloat =
            [ "" ]
                |> generateFloat

        csvFloatdata =
            columnNameFloat :: dataGenerateFloat

        _ =
            Debug.log "foo_float_data.csv" csvFloatdata
    in
    test "Testing generation of foo float data" (\_ -> Expect.equal (List.length csvFloatdata) 10)
