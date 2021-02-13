module Morphir.IR.DataCodec exposing (decodeData, encodeData)

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.Type as Type exposing (ResolvedType, Type)
import Morphir.IR.Value as Value exposing (RawValue, Value)


encodeData : ResolvedType -> Result String (RawValue -> Encode.Value)
encodeData tpe =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], moduleName, localName ) args ->
            case ( moduleName, localName, args ) of
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

                _ ->
                    Debug.todo "implement"

        _ ->
            Debug.todo "implement"


decodeData : ResolvedType -> Result String (Decode.Decoder RawValue)
decodeData tpe =
    case tpe of
        Type.Record _ fields ->
            fields
                |> List.foldr
                    (\field resultSoFar ->
                        resultSoFar
                            |> Result.andThen
                                (\decoderSoFar ->
                                    decodeData field.tpe
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
                    Ok (Decode.map (\value -> Value.Literal () (StringLiteral value)) Decode.string)

                ( [ [ "string" ] ], [ "string" ], [] ) ->
                    Ok (Decode.map (\value -> Value.Literal () (StringLiteral value)) Decode.string)

                ( [ [ "list" ] ], [ "list" ], [ itemType ] ) ->
                    decodeData itemType
                        |> Result.map
                            (\itemDecoder ->
                                Decode.list itemDecoder
                                    |> Decode.map (Value.List ())
                            )

                ( [ [ "maybe" ] ], [ "maybe" ], [ itemType ] ) ->
                    Debug.todo "Todo Maybe Type"

                _ ->
                    Debug.todo "Todo Custom Type"

        Type.Tuple _ args ->
            args
                |> List.foldr
                    (\argValue resultSoFar ->
                        resultSoFar
                            |> Result.andThen
                                (\decoderSoFar ->
                                    decodeData argValue
                                        |> Result.map
                                            (\fieldDecoder ->
                                                decoderSoFar
                                                    |> Decode.andThen
                                                        (\fieldValuesSoFar ->
                                                            fieldDecoder
                                                                |> Decode.map
                                                                    (\fieldValue ->
                                                                        fieldValue :: fieldValuesSoFar
                                                                    )
                                                        )
                                            )
                                )
                    )
                    (Ok (Decode.succeed []))
                |> Result.map (\decoder -> Decode.map (Value.Tuple ()) decoder)

        _ ->
            Err "Cannot Decode this type"
