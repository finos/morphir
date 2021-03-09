module Morphir.IR.Type.DataCodec exposing (decodeData, encodeData)

import Dict exposing (Dict)
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR exposing (IR)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.SDK.Maybe exposing (just, nothing)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, Value)
import Morphir.ListOfResults as ListOfResults


encodeData : IR -> Type ta -> Result String (RawValue -> Encode.Value)
encodeData ir tpe =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], moduleName, localName ) args ->
            case ( moduleName, localName, args ) of
                ( [ [ "basics" ] ], [ "bool" ], [] ) ->
                    Ok
                        (\value ->
                            case value of
                                Value.Literal _ (BoolLiteral v) ->
                                    Encode.bool v

                                _ ->
                                    Encode.null
                        )

                ( [ [ "char" ] ], [ "char" ], [] ) ->
                    Ok
                        (\value ->
                            case value of
                                Value.Literal _ (CharLiteral v) ->
                                    Encode.string (String.fromChar v)

                                _ ->
                                    Encode.null
                        )

                ( [ [ "string" ] ], [ "string" ], [] ) ->
                    Ok
                        (\value ->
                            case value of
                                Value.Literal _ (StringLiteral v) ->
                                    Encode.string v

                                _ ->
                                    Encode.null
                        )

                ( [ [ "basics" ] ], [ "int" ], [] ) ->
                    Ok
                        (\value ->
                            case value of
                                Value.Literal _ (IntLiteral v) ->
                                    Encode.int v

                                _ ->
                                    Encode.null
                        )

                ( [ [ "basics" ] ], [ "float" ], [] ) ->
                    Ok
                        (\value ->
                            case value of
                                Value.Literal _ (FloatLiteral v) ->
                                    Encode.float v

                                _ ->
                                    Encode.null
                        )

                ( [ [ "list" ] ], [ "list" ], [ itemType ] ) ->
                    encodeData ir itemType
                        |> Result.map
                            (\encodeItem value ->
                                case value of
                                    Value.List _ items ->
                                        Encode.list encodeItem items

                                    _ ->
                                        Encode.null
                            )

                ( [ [ "maybe" ] ], [ "maybe" ], [ itemType ] ) ->
                    encodeData ir itemType
                        |> Result.map
                            (\encodeItem value ->
                                case value of
                                    Value.Apply () (Value.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) v ->
                                        encodeItem v

                                    Value.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ) ->
                                        Encode.null

                                    _ ->
                                        Encode.null
                            )

                _ ->
                    Debug.todo "implement"

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
                                    |> List.filterMap
                                        (\( fieldName, fieldEncoder ) ->
                                            fieldValues
                                                |> Dict.get fieldName
                                                |> Maybe.map fieldEncoder
                                                |> Maybe.map (Tuple.pair (fieldName |> Name.toCamelCase))
                                        )
                                    |> Encode.object

                            _ ->
                                Encode.null
                    )

        Type.Tuple _ elemTypes ->
            elemTypes
                |> List.map (encodeData ir)
                |> ListOfResults.liftFirstError
                |> Result.map
                    (\elemEncoders value ->
                        case value of
                            Value.Tuple _ elems ->
                                Encode.list identity
                                    (List.map2
                                        identity
                                        elemEncoders
                                        elems
                                    )

                            _ ->
                                Encode.null
                    )

        _ ->
            Debug.todo "implement"


decodeData : IR -> Type ta -> Result String (Decode.Decoder RawValue)
decodeData ir tpe =
    case tpe of
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

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], moduleName, localName ) args ->
            case ( moduleName, localName, args ) of
                ( [ [ "basics" ] ], [ "bool" ], [] ) ->
                    Ok (Decode.map (\value -> Value.Literal () (BoolLiteral value)) Decode.bool)

                ( [ [ "basics" ] ], [ "int" ], [] ) ->
                    Ok (Decode.map (\value -> Value.Literal () (IntLiteral value)) Decode.int)

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

        Type.Tuple _ elemTypes ->
            elemTypes
                |> List.foldr
                    (\argValue ( index, resultSoFar ) ->
                        ( index - 1
                        , resultSoFar
                            |> Result.andThen
                                (\decoderSoFar ->
                                    decodeData ir argValue
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
