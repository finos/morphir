module Morphir.IR.ValueFuzzer exposing (boolFuzzer, charFuzzer, floatFuzzer, fromType, intFuzzer, listFuzzer, maybeFuzzer, recordFuzzer, stringFuzzer, tupleFuzzer)

import Fuzz exposing (Fuzzer)
import Morphir.IR exposing (IR)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name exposing (Name)
import Morphir.IR.SDK.Maybe exposing (just, nothing)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, TypedValue)


fromType : IR -> Type ta -> Fuzzer RawValue
fromType ir tpe =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], moduleName, localName ) args ->
            case ( moduleName, localName, args ) of
                ( [ [ "basics" ] ], [ "bool" ], [] ) ->
                    boolFuzzer

                ( [ [ "char" ] ], [ "char" ], [] ) ->
                    charFuzzer

                ( [ [ "string" ] ], [ "string" ], [] ) ->
                    stringFuzzer

                ( [ [ "basics" ] ], [ "int" ], [] ) ->
                    intFuzzer

                ( [ [ "basics" ] ], [ "float" ], [] ) ->
                    floatFuzzer

                ( [ [ "list" ] ], [ "list" ], [ itemType ] ) ->
                    listFuzzer (fromType ir itemType)

                ( [ [ "maybe" ] ], [ "maybe" ], [ itemType ] ) ->
                    maybeFuzzer (fromType ir itemType)

                _ ->
                    Debug.todo "implement"

        Type.Record _ fieldTypes ->
            recordFuzzer (fieldTypes |> List.map (\field -> ( field.name, fromType ir field.tpe )))

        Type.Tuple _ elemTypes ->
            tupleFuzzer (elemTypes |> List.map (fromType ir))

        _ ->
            Debug.todo "implement"


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


tupleFuzzer : List (Fuzzer RawValue) -> Fuzzer RawValue
tupleFuzzer elemFuzzers =
    elemFuzzers
        |> List.foldr
            (\elemFuzzer fuzzerSoFar ->
                Fuzz.map2
                    (\elemsSoFar fieldValue ->
                        fieldValue :: elemsSoFar
                    )
                    fuzzerSoFar
                    elemFuzzer
            )
            (Fuzz.constant [])
        |> Fuzz.map (Value.Tuple ())


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
