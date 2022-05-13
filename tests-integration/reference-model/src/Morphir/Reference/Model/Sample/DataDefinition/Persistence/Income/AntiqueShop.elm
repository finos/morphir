module Morphir.Reference.Model.Sample.DataDefinition.Persistence.Supply.AntiqueShop exposing (..)

import Morphir.Reference.Model.Sample.DataDefinition.Field.Age exposing (Age)
import Morphir.Reference.Model.Sample.DataDefinition.Field.Price exposing (Price)
import Morphir.Reference.Model.Sample.DataDefinition.Field.Report exposing (FeedBack)
import Morphir.Reference.Model.Sample.Field.Category exposing (Category)


type alias Antique =
    { category : Maybe Category
    , product : Product
    , priceValue : Price
    , ageOfItem : Age
    , handMade : Bool
    , requiresExpert : Bool
    , expertFeedback : Maybe FeedBack
    , report : Maybe String
    }


type Product
    = Paintings
    | Knife
    | Plates
    | Furniture
    | HistoryWritings


productFromID : Int -> Maybe Product
productFromID id =
    case id of
        1 ->
            Just Paintings

        2 ->
            Just Knife

        3 ->
            Just Plates

        4 ->
            Just Furniture

        _ ->
            Nothing


antiqueItem1 : Product
antiqueItem1 =
    Paintings


antiqueItem2 : Product
antiqueItem2 =
    Knife


antiqueItem3 : Product
antiqueItem3 =
    Plates


antiqueItem4 : Product
antiqueItem4 =
    Furniture


allAntiqueProducts : List Product
allAntiqueProducts =
    [ Paintings
    , Knife
    , Plates
    , Furniture
    ]
