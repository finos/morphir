module Morphir.File.FileChanges exposing (..)

import Dict exposing (Dict)
import Morphir.File.Path exposing (Path)
import Set exposing (Set)


{-| Data structure to capture file changes.

It should serialize into this JSON format:

    { "path1": [ "Insert", "..file content..." ]
    , "path2": [ "Update", "..file content..." ]
    }

-}
type alias FileChanges =
    Dict Path Change


type Change
    = Insert String
    | Update String
    | Delete


type alias FileChangesByType =
    { inserts : Dict Path String
    , updates : Dict Path String
    , deletes : Set Path
    }


type Updates
    = Dict Path String


filter : (Path -> Change -> Bool) -> FileChanges -> FileChanges
filter f fileChanges =
    fileChanges
        |> Dict.filter f


partitionByType : FileChanges -> FileChangesByType
partitionByType fileChanges =
    { inserts =
        fileChanges
            |> Dict.toList
            |> List.filterMap
                (\( path, fileChange ) ->
                    case fileChange of
                        Insert content ->
                            Just ( path, content )

                        _ ->
                            Nothing
                )
            |> Dict.fromList
    , updates =
        fileChanges
            |> Dict.toList
            |> List.filterMap
                (\( path, fileChange ) ->
                    case fileChange of
                        Update content ->
                            Just ( path, content )

                        _ ->
                            Nothing
                )
            |> Dict.fromList
    , deletes =
        fileChanges
            |> Dict.toList
            |> List.filterMap
                (\( path, fileChange ) ->
                    case fileChange of
                        Delete ->
                            Just path

                        _ ->
                            Nothing
                )
            |> Set.fromList
    }
