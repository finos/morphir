{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}


module Morphir.SDK.List exposing (innerJoin, leftJoin)

{-| Extra utilities on lists.

@docs innerJoin, leftJoin

-}


{-| Returns all elements of a list except for the last.

    init [ 1, 2, 3 ] == Just [ 1, 2 ]

    init [] == Nothing

-}
init : List a -> Maybe (List a)
init list =
    list
        |> List.reverse
        |> List.tail
        |> Maybe.map List.reverse


{-| Simulates a SQL inner-join.

    dataSetA =
        [ ( 1, "a" ), ( 2, "b" ) ]

    dataSetB =
        [ ( 3, "C" ), ( 2, "B" ) ]

    dataSetA
        |> innerJoin dataSetB
            (\a b ->
               Tuple.first a == Tuple.first b
            ) ==
            [ ( ( 2, "b" ), ( 2, "B" ) )
            ]

-}
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


{-| Simulates a SQL left-outer-join.

    dataSetA =
        [ ( 1, "a" ), ( 2, "b" ) ]

    dataSetB =
        [ ( 3, "C" ), ( 2, "B" ) ]

    dataSetA
        |> leftJoin dataSetB
            (\a b ->
               Tuple.first a == Tuple.first b
            ) ==
            [ ( ( 1, "a" ), Nothing )
            , ( ( 2, "b" ), Just ( 2, "B" ) )
            ]

-}
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
