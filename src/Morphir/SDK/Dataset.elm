module Morphir.SDK.Dataset exposing (Dataset)

import Dict exposing (Dict)


type Dataset a
    = Dataset (List a)


type GroupedDataset comparable a
    = GroupedDataset (Dict comparable (List a))


type KeyValueDataset comparable a
    = KeyValueDataset (Dict comparable a)


fromList : List a -> Dataset a
fromList =
    Dataset


map : (a -> b) -> Dataset a -> Dataset b
map f (Dataset dataList) =
    dataList
        |> List.map f
        |> Dataset


filter : (a -> Bool) -> Dataset a -> Dataset a
filter f (Dataset dataList) =
    dataList
        |> List.filter f
        |> Dataset


groupBy : (a -> comparable) -> Dataset a -> GroupedDataset comparable a
groupBy getKey (Dataset dataList) =
    dataList
        |> List.foldl
            (\a soFar ->
                soFar
                    |> Dict.update (getKey a)
                        (\valueSoFar ->
                            case valueSoFar of
                                Nothing ->
                                    Just [ a ]

                                Just group ->
                                    Just (a :: group)
                        )
            )
            Dict.empty
        |> GroupedDataset


aggregate : (List a -> b) -> GroupedDataset comparable a -> KeyValueDataset comparable b
aggregate f (GroupedDataset dataDict) =
    dataDict
        |> Dict.map
            (\key values ->
                f values
            )
        |> KeyValueDataset
