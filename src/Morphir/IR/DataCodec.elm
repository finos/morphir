module Morphir.IR.DataCodec exposing (..)

import Json.Decode as Decode
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.QName exposing (QName(..))
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)


decodeData : Distribution -> Type () -> Result String (Decode.Decoder (Value () ()))
decodeData distro tpe =
    case tpe of
        Type.Record _ fields ->
            Err "Wrong"

        --fields
        --    |> List.foldr
        --        (\field resultSoFar ->
        --            resultSoFar
        --                |> Result.andThen
        --                    (\decoderSoFar ->
        --                        decoderSoFar
        --                            |> Decode.andThen
        --                                (\fieldValuesSoFar ->
        --                                    decodeData distro field.tpe
        --                                        |> Result.map
        --                                            (\fieldDecoder ->
        --                                                Decode.field
        --                                                    (field.name |> Name.toCamelCase)
        --                                                    fieldDecoder
        --                                                    |> Decode.map
        --                                                        (\fieldValue ->
        --                                                            ( field.name, fieldValue ) :: fieldValuesSoFar
        --                                                        )
        --                                            )
        --                                )
        --                    )
        --        )
        --        (Ok (Decode.succeed []))
        --    |> Decode.map (Value.Record ())
        Type.Reference _ (( packageName, moduleName, localName ) as fQName) args ->
            case FQName.toString fQName of
                "Morphir.SDK.Basics.Int" ->
                    Ok (Decode.map (\value -> Value.Literal () (IntLiteral value)) Decode.int)

                "Morphir.SDK.Basics.Float" ->
                    Ok (Decode.map (\value -> Value.Literal () (FloatLiteral value)) Decode.float)

                "Morphir.SDK.Basics.Bool" ->
                    Ok (Decode.map (\value -> Value.Literal () (BoolLiteral value)) Decode.bool)

                "Morphir.SDK.String.String" ->
                    Ok (Decode.map (\value -> Value.Literal () (StringLiteral value)) Decode.string)

                "Morphir.SDK.List.List" ->
                    Err "Wrong"

                --Decode.list (List.head (\argValue -> decodeData distro argValue) ) args
                --Ok (Decode.map (\argValue -> decodeData distro argValue) (Decode.list args))
                _ ->
                    distro
                        |> Distribution.lookupValueDefinition (QName moduleName localName)
                        |> Maybe.map
                            (\valueDef ->
                                decodeData distro valueDef.outputType
                            )
                        |> Maybe.withDefault (Err "Cannot Decode this type")

        Type.Tuple _ listArgs ->
            listArgs
                |> List.foldr
                    (\argValue decodeSoFar ->
                        decodeSoFar
                            |> Decode.andThen
                                (\listValueSoFar ->
                                    (case decodeData distro argValue of
                                        Ok decoder ->
                                            decoder

                                        Err error ->
                                            Decode.succeed []
                                    )
                                        |> Decode.map (\listValue -> listValue :: listValueSoFar)
                                )
                    )
                    (Decode.succeed [])
                |> Decode.map (Value.Tuple ())
                |> Ok

        _ ->
            Err "Cannot Decode this type"
