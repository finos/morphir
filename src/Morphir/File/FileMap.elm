module Morphir.File.FileMap exposing (..)

import Dict exposing (Dict)


type alias FileMap =
    Dict ( List String, String ) String
