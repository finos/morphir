module Morphir.IR.Type.DataCodec exposing (decodeData, encodeData)

import Dict exposing (Dict)
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR as IR exposing (IR)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.SDK.Maybe exposing (just, nothing)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, Value)
import Morphir.ListOfResults as ListOfResults


encodeData : IR -> Type () -> Result String (RawValue -> Result String Encode.Value)
encodeData ir tpe =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], moduleName, localName ) args ->
            case ( moduleName, localName, args ) of
                ( [ [ "basics" ] ], [ "bool" ], [] ) ->
                    Ok
                        (\value ->
                            case value of
                                Value.Literal _ (BoolLiteral v) ->
                                    Ok (Encode.bool v)

                                _ ->
                                    Err (String.concat [ "Expected bool literal but found: ", Debug.toString value ])
                        )

                ( [ [ "char" ] ], [ "char" ], [] ) ->
                    Ok
                        (\value ->
                            case value of
                                Value.Literal _ (CharLiteral v) ->
                                    Ok (Encode.string (String.fromChar v))

                                _ ->
                                    Err (String.concat [ "Expected char literal but found: ", Debug.toString value ])
                        )

                ( [ [ "string" ] ], [ "string" ], [] ) ->
                    Ok
                        (\value ->
                            case value of
                                Value.Literal _ (StringLiteral v) ->
                                    Ok (Encode.string v)

                                _ ->
                                    Err (String.concat [ "Expected string literal but found: ", Debug.toString value ])
                        )

                ( [ [ "basics" ] ], [ "int" ], [] ) ->
                    Ok
                        (\value ->
                            case value of
                                Value.Literal _ (WholeNumberLiteral v) ->
                                    Ok (Encode.int v)

                                _ ->
                                    Err (String.concat [ "Expected int literal but found: ", Debug.toString value ])
                        )

                ( [ [ "basics" ] ], [ "float" ], [] ) ->
                    Ok
                        (\value ->
                            case value of
                                Value.Literal _ (FloatLiteral v) ->
                                    Ok (Encode.float v)

                                _ ->
                                    Err (String.concat [ "Expected float literal but found: ", Debug.toString value ])
                        )

                ( [ [ "list" ] ], [ "list" ], [ itemType ] ) ->
                    encodeData ir itemType
                        |> Result.map
                            (\encodeItem value ->
                                case value of
                                    Value.List _ items ->
                                        items
                                            |> List.map encodeItem
                                            |> ListOfResults.liftFirstError
                                            |> Result.map (Encode.list identity)

                                    _ ->
                                        Err (String.concat [ "Expected list but found: ", Debug.toString value ])
                            )

                ( [ [ "maybe" ] ], [ "maybe" ], [ itemType ] ) ->
                    encodeData ir itemType
                        |> Result.map
                            (\encodeItem value ->
                                case value of
                                    Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) v ->
                                        encodeItem v

                                    Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ) ->
                                        Ok Encode.null

                                    _ ->
                                        Err (String.concat [ "Expected Just or Nothing but found: ", Debug.toString value ])
                            )

                --( [ [ "result" ] ], [ "result" ], [ itemType ] ) ->
                --    encodeData ir itemType
                --        |> Result.map
                --            (\encodeItem value ->
                --                case value of
                --                    Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) v ->
                --                        encodeItem v
                --
                --                    Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error ->
                --                        encodeItem error
                --
                --                    _ ->
                --                        Err (String.concat [ "Expected Ok or Error but found: ", Debug.toString value ])
                --            )
                _ ->
                    Debug.todo "implement"

        Type.Reference _ (( typePackageName, typeModuleName, _ ) as fQName) typeArgs ->
            -- Handle references that are not part of the SDK
            ir
                |> IR.lookupTypeSpecification fQName
                |> Result.fromMaybe (String.concat [ "Cannot find reference: ", FQName.toString fQName ])
                |> Result.andThen
                    (\typeSpec ->
                        case typeSpec of
                            Type.TypeAliasSpecification typeArgNames typeExp ->
                                -- For type aliases we extract the type expression, substitute the type variables and recursively
                                -- call this function
                                let
                                    argVariables : Dict Name (Type ())
                                    argVariables =
                                        List.map2 Tuple.pair typeArgNames typeArgs
                                            |> Dict.fromList
                                in
                                typeExp
                                    |> Type.substituteTypeVariables argVariables
                                    |> encodeData ir

                            Type.OpaqueTypeSpecification _ ->
                                Err (String.concat [ "Cannot serialize opaque type: ", FQName.toString fQName ])

                            Type.CustomTypeSpecification typeArgNames constructors ->
                                let
                                    argVariables : Dict Name (Type ())
                                    argVariables =
                                        List.map2 Tuple.pair typeArgNames typeArgs
                                            |> Dict.fromList

                                    encode : RawValue -> Result String Encode.Value
                                    encode value =
                                        let
                                            encodeConstructor : RawValue -> List RawValue -> Result String Encode.Value
                                            encodeConstructor bottomFun constructorArgs =
                                                case bottomFun of
                                                    Value.Constructor _ ( constructorPackageName, constructorModuleName, constructorLocalName ) ->
                                                        if ( constructorPackageName, constructorModuleName ) == ( typePackageName, typeModuleName ) then
                                                            constructors
                                                                |> Dict.get constructorLocalName
                                                                |> Result.fromMaybe (String.concat [ "Constructor '", Name.toTitleCase constructorLocalName, "' in type '", FQName.toString fQName, "' not found." ])
                                                                |> Result.andThen
                                                                    (\constructorArgTypes ->
                                                                        constructorArgTypes
                                                                            |> List.map (Tuple.second >> Type.substituteTypeVariables argVariables >> encodeData ir)
                                                                            |> ListOfResults.liftFirstError
                                                                            |> Result.andThen
                                                                                (\constructorArgEncoders ->
                                                                                    List.map2 identity constructorArgEncoders constructorArgs
                                                                                        |> ListOfResults.liftFirstError
                                                                                        |> Result.map
                                                                                            (\encodedArgs ->
                                                                                                Encode.list identity
                                                                                                    (Encode.string (Name.toCamelCase constructorLocalName) :: encodedArgs)
                                                                                            )
                                                                                )
                                                                    )

                                                        else
                                                            Err (String.concat [ "Expected constructor for type '", FQName.toString fQName, "' but found: ", Debug.toString value ])

                                                    _ ->
                                                        Err (String.concat [ "Expected constructor but found: ", Debug.toString value ])
                                        in
                                        case value of
                                            Value.Constructor _ _ ->
                                                encodeConstructor value []

                                            Value.Apply _ fun arg ->
                                                let
                                                    ( bottomFun, args ) =
                                                        Value.uncurryApply fun arg
                                                in
                                                encodeConstructor bottomFun args

                                            _ ->
                                                Err (String.concat [ "Expected constructor but found: ", Debug.toString value ])
                                in
                                Ok encode
                    )

        Type.Record _ fieldTypes ->
            fieldTypes
                |> List.map
                    (\field ->
                        encodeData ir field.tpe
                            |> Result.map (Tuple.pair field.name)
                    )
                |> ListOfResults.liftFirstError
                |> Result.map
                    (\fieldEncoders value ->
                        case value of
                            Value.Record _ fields ->
                                let
                                    fieldValues : Dict Name RawValue
                                    fieldValues =
                                        fields
                                            |> Dict.fromList
                                in
                                fieldEncoders
                                    |> List.map
                                        (\( fieldName, fieldEncoder ) ->
                                            fieldValues
                                                |> Dict.get fieldName
                                                |> Result.fromMaybe (String.concat [ "Value for field not found: ", Name.toCamelCase fieldName ])
                                                |> Result.andThen fieldEncoder
                                                |> Result.map (Tuple.pair (fieldName |> Name.toCamelCase))
                                        )
                                    |> ListOfResults.liftFirstError
                                    |> Result.map Encode.object

                            _ ->
                                Err (String.concat [ "Expected record but found: ", Debug.toString value ])
                    )

        Type.Tuple _ elemTypes ->
            elemTypes
                |> List.map (encodeData ir)
                |> ListOfResults.liftFirstError
                |> Result.map
                    (\elemEncoders value ->
                        case value of
                            Value.Tuple _ elems ->
                                List.map2 identity elemEncoders elems
                                    |> ListOfResults.liftFirstError
                                    |> Result.map (Encode.list identity)

                            _ ->
                                Err (String.concat [ "Expected tuple but found: ", Debug.toString value ])
                    )

        a ->
           Debug.log "" a |> Debug.todo "implement"


decodeData : IR -> Type () -> Result String (Decode.Decoder RawValue)
decodeData ir tpe =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], moduleName, localName ) args ->
            case ( moduleName, localName, args ) of
                ( [ [ "basics" ] ], [ "bool" ], [] ) ->
                    Ok (Decode.map (\value -> Value.Literal () (BoolLiteral value)) Decode.bool)

                ( [ [ "basics" ] ], [ "int" ], [] ) ->
                    Ok (Decode.map (\value -> Value.Literal () (WholeNumberLiteral value)) Decode.int)

                ( [ [ "basics" ] ], [ "float" ], [] ) ->
                    Ok (Decode.map (\value -> Value.Literal () (FloatLiteral value)) Decode.float)

                ( [ [ "char" ] ], [ "char" ], [] ) ->
                    Ok
                        (Decode.string
                            |> Decode.andThen
                                (\value ->
                                    case value |> String.uncons of
                                        Just ( firstChar, _ ) ->
                                            Decode.succeed (Value.Literal () (CharLiteral firstChar))

                                        Nothing ->
                                            Decode.fail "Expected char but found empty string."
                                )
                        )

                ( [ [ "string" ] ], [ "string" ], [] ) ->
                    Ok (Decode.map (\value -> Value.Literal () (StringLiteral value)) Decode.string)

                ( [ [ "list" ] ], [ "list" ], [ itemType ] ) ->
                    decodeData ir itemType
                        |> Result.map
                            (\itemDecoder ->
                                Decode.list itemDecoder
                                    |> Decode.map (Value.List ())
                            )

                ( [ [ "maybe" ] ], [ "maybe" ], [ itemType ] ) ->
                    decodeData ir itemType
                        |> Result.map
                            (\itemDecoder ->
                                Decode.maybe itemDecoder
                                    |> Decode.map
                                        (\item ->
                                            case item of
                                                Just v ->
                                                    just () v

                                                Nothing ->
                                                    nothing ()
                                        )
                            )

                _ ->
                    Debug.todo "Todo Custom Type"

        Type.Reference _ (( typePackageName, typeModuleName, _ ) as fQName) typeArgs ->
            -- Handle references that are not part of the SDK
            ir
                |> IR.lookupTypeSpecification fQName
                |> Result.fromMaybe (String.concat [ "Cannot find reference: ", FQName.toString fQName ])
                |> Result.andThen
                    (\typeSpec ->
                        case typeSpec of
                            Type.TypeAliasSpecification typeArgNames typeExp ->
                                -- For type aliases we extract the type expression, substitute the type variables and recursively
                                -- call this function
                                let
                                    argVariables : Dict Name (Type ())
                                    argVariables =
                                        List.map2 Tuple.pair typeArgNames typeArgs
                                            |> Dict.fromList
                                in
                                typeExp
                                    |> Type.substituteTypeVariables argVariables
                                    |> decodeData ir

                            Type.OpaqueTypeSpecification _ ->
                                Err (String.concat [ "Cannot serialize opaque type: ", FQName.toString fQName ])

                            Type.CustomTypeSpecification typeArgNames constructors ->
                                let
                                    argVariables : Dict Name (Type ())
                                    argVariables =
                                        List.map2 Tuple.pair typeArgNames typeArgs
                                            |> Dict.fromList
                                in
                                Decode.index 0 Decode.string
                                    |> Decode.andThen
                                        (\tag ->
                                            let
                                                constructorLocalName : Name
                                                constructorLocalName =
                                                    Name.fromString tag

                                                decoderResult : Result String (Decode.Decoder RawValue)
                                                decoderResult =
                                                    constructors
                                                        |> Dict.get constructorLocalName
                                                        |> Result.fromMaybe (String.concat [ "Constructor '", Name.toTitleCase constructorLocalName, "' in type '", FQName.toString fQName, "' not found." ])
                                                        |> Result.andThen
                                                            (\constructorArgTypes ->
                                                                constructorArgTypes
                                                                    |> List.foldl
                                                                        (\( _, argType ) ( index, resultSoFar ) ->
                                                                            ( index + 1
                                                                            , resultSoFar
                                                                                |> Result.andThen
                                                                                    (\decoderSoFar ->
                                                                                        decodeData ir (argType |> Type.substituteTypeVariables argVariables)
                                                                                            |> Result.map
                                                                                                (\argDecoder ->
                                                                                                    decoderSoFar
                                                                                                        |> Decode.andThen
                                                                                                            (\constructorSoFar ->
                                                                                                                Decode.index index argDecoder
                                                                                                                    |> Decode.map
                                                                                                                        (\argValue ->
                                                                                                                            Value.Apply () constructorSoFar argValue
                                                                                                                        )
                                                                                                            )
                                                                                                )
                                                                                    )
                                                                            )
                                                                        )
                                                                        ( 1, Ok (Decode.succeed (Value.Constructor () ( typePackageName, typeModuleName, constructorLocalName ))) )
                                                                    |> Tuple.second
                                                            )
                                            in
                                            case decoderResult of
                                                Ok d ->
                                                    d

                                                Err error ->
                                                    Decode.fail error
                                        )
                                    |> Ok
                    )

        Type.Record _ fields ->
            fields
                |> List.foldr
                    (\field resultSoFar ->
                        resultSoFar
                            |> Result.andThen
                                (\decoderSoFar ->
                                    decodeData ir field.tpe
                                        |> Result.map
                                            (\fieldDecoder ->
                                                decoderSoFar
                                                    |> Decode.andThen
                                                        (\fieldValuesSoFar ->
                                                            Decode.field
                                                                (field.name |> Name.toCamelCase)
                                                                fieldDecoder
                                                                |> Decode.map
                                                                    (\fieldValue ->
                                                                        ( field.name, fieldValue ) :: fieldValuesSoFar
                                                                    )
                                                        )
                                            )
                                )
                    )
                    (Ok (Decode.succeed []))
                |> Result.map (\decoder -> Decode.map (Value.Record ()) decoder)

        Type.Tuple _ elemTypes ->
            elemTypes
                |> List.foldr
                    (\elemType ( index, resultSoFar ) ->
                        ( index - 1
                        , resultSoFar
                            |> Result.andThen
                                (\decoderSoFar ->
                                    decodeData ir elemType
                                        |> Result.map
                                            (\fieldDecoder ->
                                                decoderSoFar
                                                    |> Decode.andThen
                                                        (\fieldValuesSoFar ->
                                                            Decode.index index fieldDecoder
                                                                |> Decode.map
                                                                    (\fieldValue ->
                                                                        fieldValue :: fieldValuesSoFar
                                                                    )
                                                        )
                                            )
                                )
                        )
                    )
                    ( List.length elemTypes - 1, Ok (Decode.succeed []) )
                |> Tuple.second
                |> Result.map (Decode.map (Value.Tuple ()))

        _ ->
            Err "Cannot Decode this type"
