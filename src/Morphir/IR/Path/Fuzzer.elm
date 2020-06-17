module Morphir.IR.Path.Fuzzer exposing (..)

{-| Path fuzzer.
-}

import Fuzz exposing (Fuzzer)
import Morphir.IR.Name.Fuzzer exposing (fuzzName)
import Morphir.IR.Path as Path exposing (Path)


fuzzPath : Fuzzer Path
fuzzPath =
    Fuzz.list fuzzName
        |> Fuzz.map (List.take 3)
        |> Fuzz.map Path.fromList
