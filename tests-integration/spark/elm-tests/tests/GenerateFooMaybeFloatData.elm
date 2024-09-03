module GenerateFooMaybeFloatData exposing (..)

import Expect exposing (Expectation)
import GenerateAntiquesData exposing (..)
import Test exposing (..)


columnNameFloat : String
columnNameFloat =
    "foo"


generateMaybeFloat : List String -> List String
generateMaybeFloat =
    generator [ "9.99", "8.13", "4.675432", "347484.888", "12314252.99", "134890.0", "0.0", "444.00000", "7837539.23", "" ]


testFooMaybeFloatGeneration : Test
testFooMaybeFloatGeneration =
    let
        dataGenerateMaybeFloat =
            [ "" ]
                |> generateMaybeFloat

        csvMaybeFloatdata =
            columnNameFloat :: dataGenerateMaybeFloat

        _ =
            Debug.log "foo_maybe_float_data.csv" csvMaybeFloatdata
    in
    test "Testing generation of foo maybe float data" (\_ -> Expect.equal (List.length csvMaybeFloatdata) 11)
