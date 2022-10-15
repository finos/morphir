module GenerateAntiqueAgeData exposing (..)

import Expect exposing (Expectation)
import GenerateAntiquesData exposing (..)
import Test exposing (..)


columnNamesAge : String
columnNamesAge =
    "ageOfItem"


testAgeDataGeneration : Test
testAgeDataGeneration =
    let
        dataListAgedata =
            [ "" ]
                |> generateAgeOfItem

        csvAgedata =
            columnNamesAge :: dataListAgedata

        _ =
            Debug.log "antique_age_data.csv" csvAgedata
    in
    test "Testing generation of antique age data" (\_ -> Expect.equal (List.length csvAgedata) 9)
