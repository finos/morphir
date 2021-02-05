module Morphir.IR.DataCodec exposing (..)

import Json.Decode as Decode
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.QName exposing (QName(..))
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
            case FQName.toString fQName of
                "Morphir.SDK.Basics.Int" ->
                    Ok (Decode.map (\value -> Value.Literal () (IntLiteral value)) Decode.int)

                "Morphir.SDK.Basics.Float" ->
                    Ok (Decode.map (\value -> Value.Literal () (FloatLiteral value)) Decode.float)

                "Morphir.SDK.Basics.Bool" ->
                    Ok (Decode.map (\value -> Value.Literal () (BoolLiteral value)) Decode.bool)

                "Morphir.SDK.Char.Char" ->
                    Ok (Decode.map (\value -> Value.Literal () (StringLiteral value)) Decode.string)

                "Morphir.SDK.String.String" ->
                    Ok (Decode.map (\value -> Value.Literal () (StringLiteral value)) Decode.string)

                "Morphir.SDK.List.List" ->
                    Err "Cannot Decode this type"

                _ ->
                    Err "Cannot Decode this type"

        _ ->
            Err "Cannot Decode this type"
