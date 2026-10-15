module SparkTests.DataDefinition.Persistence.Expenditure.Bills exposing (..)

import SparkTests.DataDefinition.Field.Name exposing (Name)
import SparkTests.DataDefinition.Field.Price exposing (Price)


type alias Bills =
    { name : Name
    , price : Price
    }


type Product
    = WaterBill
    | LightBill
    | InternetBill


productFromID : Int -> Maybe Product
productFromID id =
    case id of
        1 ->
            Just WaterBill

        2 ->
            Just LightBill

        3 ->
            Just InternetBill

        _ ->
            Nothing


utilProduct1 : Product
utilProduct1 =
    WaterBill


utilProduct2 : Product
utilProduct2 =
    LightBill


utilProduct3 : Product
utilProduct3 =
    InternetBill
