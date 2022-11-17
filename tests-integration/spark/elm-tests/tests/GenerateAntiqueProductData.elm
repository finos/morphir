module GenerateAntiqueProductData exposing (..)

import Expect exposing (Expectation)
import GenerateAntiquesData exposing (generateProduct)
import Test exposing (..)


columnNamesProduct : String
columnNamesProduct =
    "product"


testProdDataGeneration : Test
testProdDataGeneration =
    let
        dataListProductdata =
            [ "" ]
                |> generateProduct

        csvProddata =
            columnNamesProduct :: dataListProductdata

        _ =
            Debug.log "antique_product_data.csv" csvProddata
    in
    test "Testing generation of antique test data" (\_ -> Expect.equal (List.length csvProddata) 6)
