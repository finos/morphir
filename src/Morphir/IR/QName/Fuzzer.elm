module Morphir.IR.QName.Fuzzer exposing (..)

import Fuzz exposing (Fuzzer)
import Morphir.IR.Name exposing (fuzzName)
import Morphir.IR.Path exposing (fuzzPath)
import Morphir.IR.QName exposing (QName(..))


{-| QName fuzzer.
-}
fuzzQName : Fuzzer QName
fuzzQName =
    Fuzz.map2 QName
        fuzzPath
        fuzzName
