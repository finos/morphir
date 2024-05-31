module Morphir.Elm.Generator.ValueGenerators exposing (boolValueGenerator, charValueGenerator, floatValueGenerator, fromType, intValueGenerator, listValueGenerator, maybeValueGenerator, recordValueGenerator, stringValueGenerator, tupleValueGenerator)

import Date
import Dict exposing (Dict)
import Morphir.Elm.Generator.API as Generator exposing (Generator)
import Morphir.IR.Distribution exposing (Distribution, lookupTypeSpecification)
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal as Literal
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Path exposing (Path)
import Morphir.IR.SDK.Maybe exposing (just, nothing)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue)
import Morphir.SDK.ResultList as ResultList


type alias Error =
    String


fromType : Distribution -> Type () -> Result Error (Generator RawValue)
fromType ir tpe =
    case tpe of
        Type.Reference _ (( [ [ "morphir" ], [ "s", "d", "k" ] ], moduleName, localName ) as fqn) args ->
            case ( moduleName, localName, args ) of
                ( [ [ "basics" ] ], [ "bool" ], [] ) ->
                    Ok boolValueGenerator

                ( [ [ "char" ] ], [ "char" ], [] ) ->
                    Ok charValueGenerator

                ( [ [ "string" ] ], [ "string" ], [] ) ->
                    Ok stringValueGenerator

                ( [ [ "basics" ] ], [ "int" ], [] ) ->
                    Ok intValueGenerator

                ( [ [ "basics" ] ], [ "float" ], [] ) ->
                    Ok floatValueGenerator

                ( [ [ "list" ] ], [ "list" ], [ itemType ] ) ->
                    fromType ir itemType
                        |> Result.map listValueGenerator

                ( [ [ "maybe" ] ], [ "maybe" ], [ itemType ] ) ->
                    fromType ir itemType
                        |> Result.map maybeValueGenerator

                ( [ [ "local", "date" ] ], [ "local", "date" ], _ ) ->
                    Ok localDateValueGenerator

                _ ->
                    Err ("Unhandled FQN: " ++ FQName.toString fqn)

        Type.Reference _ (( typePackageName, typeModuleName, _ ) as fQName) typeArgs ->
            -- Handle references that are not part of the SDK
            ir
                |> lookupTypeSpecification fQName
                |> Result.fromMaybe (String.concat [ "Cannot find reference: ", FQName.toString fQName ])
                |> Result.andThen
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
                                            argTypes
                                                |> List.map
                                                    (\( _, argType ) ->
                                                        fromType ir
                                                            (argType
                                                                |> Type.substituteTypeVariables argVariables
                                                            )
                                                    )
                                                |> ResultList.keepFirstError
                                                |> Result.map
                                                    (\ctorGenerator ->
                                                        ( ctorName
                                                        , ctorGenerator
                                                        )
                                                    )
                                        )
                                    |> ResultList.keepFirstError
                                    |> Result.andThen (customValueGenerator typePackageName typeModuleName)

                            Type.DerivedTypeSpecification _ config ->
                                fromType ir config.baseType
                    )

        Type.Record _ fieldTypes ->
            fieldTypes
                |> List.map
                    (\field ->
                        fromType ir field.tpe
                            |> Result.map
                                (\t ->
                                    ( field.name
                                    , t
                                    )
                                )
                    )
                |> ResultList.keepFirstError
                |> Result.map recordValueGenerator

        Type.Tuple _ elemTypes ->
            elemTypes
                |> List.map (fromType ir)
                |> ResultList.keepFirstError
                |> Result.map tupleValueGenerator

        Type.ExtensibleRecord a name fields ->
            fields
                |> List.map
                    (\field ->
                        fromType ir field.tpe
                            |> Result.map
                                (\t ->
                                    ( field.name
                                    , t
                                    )
                                )
                    )
                |> ResultList.keepFirstError
                |> Result.map recordValueGenerator

        Type.Unit a ->
            Generator.constant (Value.Unit ())
                |> Ok

        Type.Function _ _ _ ->
            Err "Function types not supported"

        Type.Variable _ _ ->
            Err "Variable types not supported"


boolValueGenerator : Generator RawValue
boolValueGenerator =
    Generator.bool
        |> Generator.map (Literal.BoolLiteral >> Value.Literal ())


charValueGenerator : Generator RawValue
charValueGenerator =
    Generator.anyChar
        |> Generator.map (Literal.CharLiteral >> Value.Literal ())


stringValueGenerator : Generator RawValue
stringValueGenerator =
    Generator.string
        |> Generator.map (Literal.StringLiteral >> Value.Literal ())


intValueGenerator : Generator RawValue
intValueGenerator =
    Generator.int
        |> Generator.map (Literal.WholeNumberLiteral >> Value.Literal ())


floatValueGenerator : Generator RawValue
floatValueGenerator =
    Generator.niceFloat
        |> Generator.map (Literal.FloatLiteral >> Value.Literal ())


listValueGenerator : Generator RawValue -> Generator RawValue
listValueGenerator itemGenerator =
    Generator.list itemGenerator
        |> Generator.map (Value.List ())


maybeValueGenerator : Generator RawValue -> Generator RawValue
maybeValueGenerator itemGenerator =
    Generator.maybe itemGenerator
        |> Generator.map
            (\item ->
                case item of
                    Just v ->
                        just () v

                    Nothing ->
                        nothing ()
            )


localDateValueGenerator : Generator RawValue
localDateValueGenerator =
    Generator.map
        (\int ->
            Date.fromRataDie int
                |> Date.toIsoString
                |> Literal.StringLiteral
                |> Value.Literal ()
                |> Value.Apply () (Value.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "local", "date" ] ], [ "from", "i", "s", "o" ] ))
        )
        (Generator.intRange 100000 2000000)


tupleValueGenerator : List (Generator RawValue) -> Generator RawValue
tupleValueGenerator elemGenerators =
    elemGenerators
        |> List.foldr
            (\elemGenerator elemGeneratorSoFar ->
                Generator.map2
                    (\elemsSoFar fieldValue ->
                        fieldValue :: elemsSoFar
                    )
                    elemGeneratorSoFar
                    elemGenerator
            )
            (Generator.constant [])
        |> Generator.map (Value.Tuple ())


recordValueGenerator : List ( Name, Generator RawValue ) -> Generator RawValue
recordValueGenerator fieldValueGenerators =
    fieldValueGenerators
        |> List.foldr
            (\( fieldName, fieldValueGenerator ) generatorSoFar ->
                Generator.map2
                    (\fieldsSoFar fieldValue ->
                        ( fieldName, fieldValue ) :: fieldsSoFar
                    )
                    generatorSoFar
                    fieldValueGenerator
            )
            (Generator.constant [])
        |> Generator.map (Dict.fromList >> Value.Record ())


customValueGenerator : Path -> Path -> List ( Name, List (Generator RawValue) ) -> Result Error (Generator RawValue)
customValueGenerator packageName moduleName ctorByParamGenerators =
    let
        ctorGenerators =
            ctorByParamGenerators
                |> List.map
                    (\( ctorName, argFuzzers ) ->
                        argFuzzers
                            |> List.foldl
                                (\argFuzzer ctorSoFar ->
                                    Generator.map2 (Value.Apply ())
                                        ctorSoFar
                                        argFuzzer
                                )
                                (Generator.constant (Value.Constructor () ( packageName, moduleName, ctorName )))
                    )
    in
    case ctorGenerators of
        [] ->
            Err "No Constructors"

        firstCtor :: otherCtors ->
            Generator.map2 Generator.oneOf
                firstCtor
                (Generator.combine otherCtors)
                |> Generator.andThen identity
                |> Ok
