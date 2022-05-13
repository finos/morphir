module Morphir.Reference.Model.Sample.DataDefinition.Persistence.Supply.GroceryShop exposing (..)

import Morphir.Reference.Model.Sample.DataDefinition.Field.Price exposing (Price)
import Morphir.Reference.Model.Sample.Field.Category exposing (Category)


type alias Grocery =
    { category : Maybe Category
    , product : Product
    , priceValue : Price
    }


type Product
    = Vegetable
    | Fruit


productFromID : Int -> Maybe Product
productFromID id =
    case id of
        1 ->
            Just Vegetable

        2 ->
            Just Fruit

        _ ->
            Nothing


groceryItem1 : Product
groceryItem1 =
    Vegetable


groceryItem2 : Product
groceryItem2 =
    Fruit
