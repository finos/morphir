module SparkTests.DataDefinition.Persistence.Income.ElectronicShop exposing (..)

import SparkTests.DataDefinition.Field.Date exposing (Date)
import SparkTests.DataDefinition.Field.Price exposing (Price)


type alias Electronic =
    { product : Product
    , priceValue : Price
    , yearOfManufacture : Date
    }


type Product
    = MacBook_M1
    | Lenovo_Yoga
    | Alienware


productFromID : Int -> Maybe Product
productFromID id =
    case id of
        1 ->
            Just MacBook_M1

        2 ->
            Just Lenovo_Yoga

        3 ->
            Just Alienware

        _ ->
            Nothing


electronicProduct1 : Product
electronicProduct1 =
    MacBook_M1


electronicProduct2 : Product
electronicProduct2 =
    Lenovo_Yoga


electronicProduct3 : Product
electronicProduct3 =
    Alienware
