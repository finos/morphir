module Morphir.IR.ValueFuzzer exposing (boolFuzzer, charFuzzer, floatFuzzer, intFuzzer, listFuzzer, stringFuzzer)

import Fuzz exposing (Fuzzer)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Value as Value exposing (RawValue, TypedValue)


boolFuzzer : Fuzzer RawValue
boolFuzzer =
    Fuzz.bool
        |> Fuzz.map (BoolLiteral >> Value.Literal ())


charFuzzer : Fuzzer RawValue
charFuzzer =
    Fuzz.char
        |> Fuzz.map (CharLiteral >> Value.Literal ())


stringFuzzer : Fuzzer RawValue
stringFuzzer =
    Fuzz.string
        |> Fuzz.map (StringLiteral >> Value.Literal ())


intFuzzer : Fuzzer RawValue
intFuzzer =
    Fuzz.int
        |> Fuzz.map (IntLiteral >> Value.Literal ())


floatFuzzer : Fuzzer RawValue
floatFuzzer =
    Fuzz.float
        |> Fuzz.map (FloatLiteral >> Value.Literal ())


listFuzzer : Fuzzer RawValue -> Fuzzer RawValue
listFuzzer itemFuzzer =
    Fuzz.list itemFuzzer
        |> Fuzz.map (Value.List ())
