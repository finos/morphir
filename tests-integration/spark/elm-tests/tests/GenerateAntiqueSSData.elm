module GenerateAntiqueSSData exposing (testASubsetDataGeneration)

import Expect exposing (Expectation)
import GenerateAntiquesData exposing (..)
import Test exposing (..)


columnNamesSS : String
columnNamesSS =
    "name,ageOfItem,product,report"


testASubsetDataGeneration : Test
testASubsetDataGeneration =
    let
        dataListSSdata =
            [ "" ]
                |> generateAgeOfItem
                |> generateProduct
                |> List.indexedMap
                    (\index item ->
                        let
                            itemWithReport =
                                item ++ ",Report #" ++ String.fromInt (index + 1)

                            itemWithNoReport =
                                item ++ ","

                            nameWreport =
                                ",item " ++ String.fromInt (index + 3287) ++ itemWithReport

                            nameWnoReport =
                                ",item " ++ String.fromInt (index + 896539) ++ itemWithNoReport
                        in
                        [ nameWreport, nameWnoReport ]
                    )
                |> flatten

        csvSSdata =
            columnNamesSS :: dataListSSdata

        _ =
            Debug.log "antique_subset_data.csv" csvSSdata
    in
    test "Testing generation of antique subset test data" (\_ -> Expect.equal (List.length csvSSdata) 81)
