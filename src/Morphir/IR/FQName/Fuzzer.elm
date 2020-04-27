module Morphir.IR.FQName.Fuzzer exposing (..)

{-| FQName fuzzer.
-}

import Fuzz exposing (Fuzzer)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Name.Fuzzer exposing (fuzzName)
import Morphir.IR.Path.Fuzzer exposing (fuzzPath)


fuzzFQName : Fuzzer FQName
fuzzFQName =
    Fuzz.map3 FQName
        fuzzPath
        fuzzPath
        fuzzName
