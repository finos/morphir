module Morphir.Reference.Model.Sample.DataDefinition.Persistence.Demand.Bills exposing (..)

import Morphir.Reference.Model.Sample.DataDefinition.Field.Name exposing (Name)
import Morphir.Reference.Model.Sample.DataDefinition.Field.Price exposing (Price)


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
