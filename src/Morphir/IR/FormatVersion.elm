module Morphir.IR.FormatVersion exposing (..)

import Morphir.IR.Distribution exposing (Distribution)


type alias VersionedDistribution =
    { formatVersion : Int
    , distribution : Distribution
    }
