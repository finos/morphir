module Morphir.SDK.List exposing (..)


innerJoin : List b -> (a -> b -> Bool) -> List a -> List ( a, b )
innerJoin listB onPredicate listA =
    listA
        |> List.concatMap
            (\a ->
                listB
                    |> List.filterMap
                        (\b ->
                            if onPredicate a b then
                                Just ( a, b )

                            else
                                Nothing
                        )
            )


leftJoin : List b -> (a -> b -> Bool) -> List a -> List ( a, Maybe b )
leftJoin listB onPredicate listA =
    listA
        |> List.concatMap
            (\a ->
                let
                    matchingRows =
                        listB
                            |> List.filterMap
                                (\b ->
                                    if onPredicate a b then
                                        Just ( a, Just b )

                                    else
                                        Nothing
                                )
                in
                if List.isEmpty matchingRows then
                    [ ( a, Nothing ) ]

                else
                    matchingRows
            )


rightJoin : List b -> (a -> b -> Bool) -> List a -> List ( Maybe a, b )
rightJoin listB onPredicate listA =
    listB
        |> List.concatMap
            (\b ->
                let
                    matchingRows =
                        listA
                            |> List.filterMap
                                (\a ->
                                    if onPredicate a b then
                                        Just ( Just a, b )

                                    else
                                        Nothing
                                )
                in
                if List.isEmpty matchingRows then
                    [ ( Nothing, b ) ]

                else
                    matchingRows
            )
