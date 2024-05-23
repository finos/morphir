module Morphir.File.FileSnapshot exposing (..)

import Dict exposing (Dict)
import Morphir.File.FileChanges as FileChanges exposing (FileChanges)
import Morphir.File.Path exposing (Path)


type alias Content =
    String


type alias FileSnapshot =
    Dict Path Content


filter : (Path -> Content -> Bool) -> FileSnapshot -> FileSnapshot
filter f fileSnapshot =
    fileSnapshot
        |> Dict.filter f


toInserts : FileSnapshot -> FileChanges
toInserts fileSnapshot =
    fileSnapshot
        |> Dict.map
            (\_ content ->
                FileChanges.Insert content
            )
