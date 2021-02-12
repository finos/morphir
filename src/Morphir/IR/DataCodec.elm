module Morphir.IR.DataCodec exposing (..)

import Json.Decode as Decode
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)


decodeData : Type () -> Result String (Decode.Decoder (Value () ()))
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

        Type.Reference _ (( packageName, moduleName, localName ) as fQName) args ->
            case fQName of
                ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "bool" ] ) ->
                    Ok (Decode.map (\value -> Value.Literal () (BoolLiteral value)) Decode.bool)

                ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) ->
                    Ok (Decode.map (\value -> Value.Literal () (IntLiteral value)) Decode.int)

                ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) ->
                    Ok (Decode.map (\value -> Value.Literal () (FloatLiteral value)) Decode.float)

                ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "char" ] ], [ "char" ] ) ->
                    Ok (Decode.map (\value -> Value.Literal () (StringLiteral value)) Decode.string)

                ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) ->
                    Ok (Decode.map (\value -> Value.Literal () (StringLiteral value)) Decode.string)

                ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) ->
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
                        |> Result.map (\decoder -> Decode.map (Value.List ()) decoder)

                ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "maybe" ] ) ->
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
