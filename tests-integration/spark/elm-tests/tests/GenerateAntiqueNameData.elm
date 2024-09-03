module GenerateAntiqueNameData exposing (..)

import Expect exposing (Expectation)
import GenerateAntiquesData exposing (..)
import Test exposing (..)


columnNamesName : String
columnNamesName =
    "name"


generateName : List String -> List String
generateName =
    generator [ "Upright Chair", "Small Table", "Bowie Knife", "Table Lamp", "Sofa", "Side Table", "Item1", "Item3423", "Item290", "Item1789", "Item786543", "Item7868" ]


testNameDataGeneration : Test
testNameDataGeneration =
    let
        dataListNamedata =
            [ "" ]
                |> generateName

        csvNamedata =
            columnNamesName :: dataListNamedata

        _ =
            Debug.log "antique_name_data.csv" csvNamedata
    in
    test "Testing generation of antique name data" (\_ -> Expect.equal (List.length csvNamedata) 13)
