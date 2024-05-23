module GenerateFooMaybeBoolData exposing (..)

import Expect exposing (Expectation)
import GenerateAntiquesData exposing (..)
import Test exposing (..)


columnNameBool : String
columnNameBool =
    "foo"


generateMaybeBool : List String -> List String
generateMaybeBool =
    generator [ "True", "False", ""]


testFooMaybeBoolGeneration : Test
testFooMaybeBoolGeneration =
    let
        dataGenerateMaybeBool =
            [ "" ]
                |> generateMaybeBool

        csvMaybeBooldata =
            columnNameBool :: dataGenerateMaybeBool

        _ =
            Debug.log "foo_maybe_bool_data.csv" csvMaybeBooldata
    in
    test "Testing generation of foo maybe bool data" (\_ -> Expect.equal (List.length csvMaybeBooldata) 4)
