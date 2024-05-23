module GenerateFooIntData exposing (..)

import Expect exposing (Expectation)
import GenerateAntiquesData exposing (..)
import Test exposing (..)


columnNameInt : String
columnNameInt =
    "foo"


generateInt : List String -> List String
generateInt =
    generator [ "20", "2879", "644", "90", "5689987", "567", "44444", "1000", "34", "5", "13" ]


testFooIntGeneration : Test
testFooIntGeneration =
    let
        dataGenerateInt =
            [ "" ]
                |> generateInt

        csvIntdata =
            columnNameInt :: dataGenerateInt

        _ =
            Debug.log "foo_int_data.csv" csvIntdata
    in
    test "Testing generation of foo int data" (\_ -> Expect.equal (List.length csvIntdata) 12)
