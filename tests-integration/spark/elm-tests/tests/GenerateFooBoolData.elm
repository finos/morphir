module GenerateFooBoolData exposing (..)

import Expect exposing (Expectation)
import GenerateAntiquesData exposing (..)
import Test exposing (..)


columnNameBool : String
columnNameBool =
    "foo"


generateBool : List String -> List String
generateBool =
    generator [ "True", "False" ]


testFooBoolGeneration : Test
testFooBoolGeneration =
    let
        dataGenerateBool =
            [ "" ]
                |> generateBool

        csvBooldata =
            columnNameBool :: dataGenerateBool

        _ =
            Debug.log "foo_bool_data.csv" csvBooldata
    in
    test "Testing generation of foo bool data" (\_ -> Expect.equal (List.length csvBooldata) 3)
