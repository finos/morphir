module Morphir.File.FileChanges exposing (..)

import Dict exposing (Dict)


type alias Path =
    String


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


filter : (Path -> Change -> Bool) -> FileChanges -> FileChanges
filter f fileChanges =
    fileChanges
        |> Dict.filter f
