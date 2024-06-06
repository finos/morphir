module GenerateFooStringData exposing (..)

import Expect exposing (Expectation)
import GenerateAntiquesData exposing (..)
import Test exposing (..)


columnNameString : String
columnNameString =
    "foo"


generateString : List String -> List String
generateString =
    generator [ "bar", "cat", "pool", "desk", "computer", "headphones", "glass", "can", "paper" ]


testFooStringGeneration : Test
testFooStringGeneration =
    let
        dataGenerateString =
            [ "" ]
                |> generateString

        csvStringdata =
            columnNameString :: dataGenerateString

        _ =
            Debug.log "foo_string_data.csv" csvStringdata
    in
    test "Testing generation of foo string data" (\_ -> Expect.equal (List.length csvStringdata) 10)
