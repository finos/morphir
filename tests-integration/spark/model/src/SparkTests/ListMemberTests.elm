module SparkTests.ListMemberTests exposing (..)

import SparkTests.DataDefinition.Persistence.Income.AntiqueShop exposing (..)


testEnumListMember : List { product : Product } -> List { product : Product }
testEnumListMember source =
    source
        |> List.filter
            (\a ->
                List.member a.product [ Knife, Plates ]
            )


testStringListMember : List { name : String } -> List { name : String }
testStringListMember source =
    source
        |> List.filter
            (\a ->
                List.member a.name [ "Upright Chair", "Small Table" ]
            )


testIntListMember : List { ageOfItem : Float } -> List { ageOfItem : Float }
testIntListMember source =
    source
        |> List.filter
            (\a ->
                List.member a.ageOfItem [ 19.0, 20.0, 21.0 ]
            )
