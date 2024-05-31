module GenerateFooMaybeIntData exposing (..)

import Expect exposing (Expectation)
import GenerateAntiquesData exposing (..)
import Test exposing (..)


columnNameInt : String
columnNameInt =
    "foo"


generateMaybeInt : List String -> List String
generateMaybeInt =
    generator [ "20", "2879", "644", "90", "5689987", "567", "44444", "1000", "34", "5", "13", "" ]


testFooMaybeIntGeneration : Test
testFooMaybeIntGeneration =
    let
        dataGenerateMaybeInt =
            [ "" ]
                |> generateMaybeInt

        csvMaybeIntdata =
            columnNameInt :: dataGenerateMaybeInt

        _ =
            Debug.log "foo_maybe_int_data.csv" csvMaybeIntdata
    in
    test "Testing generation of foo maybe int data" (\_ -> Expect.equal (List.length csvMaybeIntdata) 13)
