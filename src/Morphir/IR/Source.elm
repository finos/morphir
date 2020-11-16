module Morphir.IR.Source exposing (..)


type Located a
    = At Region a


type alias Region =
    { start : Location
    , end : Location
    }


type alias Location =
    { row : Int
    , column : Int
    }
