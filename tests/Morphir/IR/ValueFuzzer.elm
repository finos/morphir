module Morphir.IR.ValueFuzzer exposing (floatFuzzer, intFuzzer)

import Fuzz exposing (Fuzzer)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Value as Value exposing (RawValue, TypedValue)


intFuzzer : Fuzzer RawValue
intFuzzer =
    Fuzz.int
        |> Fuzz.map (IntLiteral >> Value.Literal ())


floatFuzzer : Fuzzer RawValue
floatFuzzer =
    Fuzz.float
        |> Fuzz.map (FloatLiteral >> Value.Literal ())
