module Morphir.IR.ValueFuzzer exposing (boolFuzzer, charFuzzer, floatFuzzer, intFuzzer, listFuzzer, maybeFuzzer, recordFuzzer, stringFuzzer)

import Fuzz exposing (Fuzzer)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name exposing (Name)
import Morphir.IR.SDK.Maybe exposing (just, nothing)
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


maybeFuzzer : Fuzzer RawValue -> Fuzzer RawValue
maybeFuzzer itemFuzzer =
    Fuzz.maybe itemFuzzer
        |> Fuzz.map
            (\item ->
                case item of
                    Just v ->
                        just () v

                    Nothing ->
                        nothing ()
            )


recordFuzzer : List ( Name, Fuzzer RawValue ) -> Fuzzer RawValue
recordFuzzer fieldFuzzers =
    fieldFuzzers
        |> List.foldr
            (\( fieldName, fieldFuzzer ) fuzzerSoFar ->
                Fuzz.map2
                    (\fieldsSoFar fieldValue ->
                        ( fieldName, fieldValue ) :: fieldsSoFar
                    )
                    fuzzerSoFar
                    fieldFuzzer
            )
            (Fuzz.constant [])
        |> Fuzz.map (Value.Record ())
