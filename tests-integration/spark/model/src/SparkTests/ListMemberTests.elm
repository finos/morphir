module SparkTests.ListMemberTests exposing (..)

import SparkTests.Types exposing (..)


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


testIntListMember : List { ageOfItem : Int } -> List { ageOfItem : Int }
testIntListMember source =
    source
        |> List.filter
            (\a ->
                List.member a.ageOfItem [ 19, 20, 21 ]
            )
