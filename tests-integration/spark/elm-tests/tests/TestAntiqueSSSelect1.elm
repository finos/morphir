module TestAntiqueSSSelect1 exposing (..)

import AntiqueSSDataSource exposing (antiqueSSDataSource)
import SparkTests.DataDefinition.Persistence.Income.AntiqueShop exposing (Antique, Product(..), productFromString, productToString)
import Csv.Encode as Encode exposing (..)
import CsvUtils exposing (..)
import SparkTests.FunctionTests exposing (..)
import Test exposing (Test)
import TestUtils exposing (executeTest)


type alias Select1list =
    { foo : String, newName : String, newReport : Maybe String, product : Product }


select1Encoder : List Select1list -> String
select1Encoder select1data =
    select1data
        |> Encode.encode
            { encoder =
                Encode.withFieldNames
                    (\select1data_ ->
                        [ ( "foo", select1data_.foo )
                        , ( "newName", select1data_.newName )
                        , ( "newReport", select1data_.newReport |> Maybe.withDefault "" )
                        , ( "product", productToString select1data_.product )
                        ]
                    )
            , fieldSeparator = ','
            }


testForSelect1 : Test
testForSelect1 =
    executeTest "testSelect1" antiqueSSDataSource testSelect1 select1Encoder
