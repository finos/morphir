module GenerateFooMaybeStringData exposing (..)

import Expect exposing (Expectation)
import GenerateAntiquesData exposing (..)
import Test exposing (..)


columnNameString : String
columnNameString =
    "foo"


generateMaybeString : List String -> List String
generateMaybeString =
    generator [ "bar", "cat", "pool", "desk", "computer", "headphones", "glass", "can", "paper", "" ]


testFooMaybeStringGeneration : Test
testFooMaybeStringGeneration =
    let
        dataGenerateMaybeString =
            [ "" ]
                |> generateMaybeString

        csvMaybeStringdata =
            columnNameString :: dataGenerateMaybeString

        _ =
            Debug.log "foo_maybe_string_data.csv" csvMaybeStringdata
    in
    test "Testing generation of foo maybe string data" (\_ -> Expect.equal (List.length csvMaybeStringdata) 11)
