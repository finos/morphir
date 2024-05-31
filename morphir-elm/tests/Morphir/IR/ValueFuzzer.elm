module Morphir.IR.ValueFuzzer exposing (boolFuzzer, charFuzzer, floatFuzzer, fromType, intFuzzer, listFuzzer, maybeFuzzer, recordFuzzer, stringFuzzer, tupleFuzzer)

import Date
import Dict exposing (Dict)
import Fuzz exposing (Fuzzer)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Path exposing (Path)
import Morphir.IR.SDK.Maybe exposing (just, nothing)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, TypedValue)


fromType : Distribution -> Type () -> Fuzzer RawValue
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

                ( [ [ "local", "date" ] ], [ "local", "date" ], _ ) ->
                    localDateFuzzer

                _ ->
                    Debug.todo "implement"

        Type.Reference _ (( typePackageName, typeModuleName, _ ) as fQName) typeArgs ->
            -- Handle references that are not part of the SDK
            ir
                |> Distribution.lookupTypeSpecification fQName
                |> Result.fromMaybe (String.concat [ "Cannot find reference: ", FQName.toString fQName ])
                |> Result.map
                    (\typeSpec ->
                        case typeSpec of
                            Type.TypeAliasSpecification typeArgNames typeExp ->
                                let
                                    argVariables : Dict Name (Type ())
                                    argVariables =
                                        List.map2 Tuple.pair typeArgNames typeArgs
                                            |> Dict.fromList
                                in
                                typeExp |> Type.substituteTypeVariables argVariables |> fromType ir

                            Type.OpaqueTypeSpecification _ ->
                                Debug.todo "implement"

                            Type.CustomTypeSpecification typeArgNames ctors ->
                                let
                                    argVariables : Dict Name (Type ())
                                    argVariables =
                                        List.map2 Tuple.pair typeArgNames typeArgs
                                            |> Dict.fromList
                                in
                                ctors
                                    |> Dict.toList
                                    |> List.map
                                        (\( ctorName, argTypes ) ->
                                            ( ctorName
                                            , argTypes
                                                |> List.map
                                                    (\( _, argType ) ->
                                                        fromType ir
                                                            (argType
                                                                |> Type.substituteTypeVariables argVariables
                                                            )
                                                    )
                                            )
                                        )
                                    |> customFuzzer typePackageName typeModuleName

                            Type.DerivedTypeSpecification _ _ ->
                                Debug.todo "implement"
                    )
                |> Result.withDefault (Fuzz.constant (Value.Unit ()))

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
        |> Fuzz.map (WholeNumberLiteral >> Value.Literal ())


floatFuzzer : Fuzzer RawValue
floatFuzzer =
    Fuzz.niceFloat
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


localDateFuzzer : Fuzzer RawValue
localDateFuzzer =
    Fuzz.map
        (\int ->
            Date.fromRataDie int
                |> Date.toIsoString
                |> StringLiteral
                |> Value.Literal ()
                |> Value.Apply () (Value.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "local", "date" ] ], [ "from", "i", "s", "o" ] ))
        )
        (Fuzz.intRange 100000 2000000)


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
        |> Fuzz.map (Dict.fromList >> Value.Record ())


customFuzzer : Path -> Path -> List ( Name, List (Fuzzer RawValue) ) -> Fuzzer RawValue
customFuzzer packageName moduleName ctorFuzzers =
    ctorFuzzers
        |> List.map
            (\( ctorName, argFuzzers ) ->
                argFuzzers
                    |> List.foldl
                        (\argFuzzer ctorSoFar ->
                            Fuzz.map2 (Value.Apply ())
                                ctorSoFar
                                argFuzzer
                        )
                        (Fuzz.constant (Value.Constructor () ( packageName, moduleName, ctorName )))
            )
        |> Fuzz.oneOf
