module Morphir.Visual.Context exposing (Context)

import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.Value exposing (RawValue)


type alias Context =
    { distribution : Distribution
    , evaluate : RawValue -> Result String RawValue
    }
