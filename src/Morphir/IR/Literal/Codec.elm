module Morphir.IR.Literal.Codec exposing (..)

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.Literal exposing (Literal(..))


encodeLiteral : Literal -> Encode.Value
encodeLiteral l =
    case l of
        BoolLiteral v ->
            Encode.list identity
                [ Encode.string "BoolLiteral"
                , Encode.bool v
                ]

        CharLiteral v ->
            Encode.list identity
                [ Encode.string "CharLiteral"
                , Encode.string (String.fromChar v)
                ]

        StringLiteral v ->
            Encode.list identity
                [ Encode.string "StringLiteral"
                , Encode.string v
                ]

        IntLiteral v ->
            Encode.list identity
                [ Encode.string "IntLiteral"
                , Encode.int v
                ]

        FloatLiteral v ->
            Encode.list identity
                [ Encode.string "FloatLiteral"
                , Encode.float v
                ]


decodeLiteral : Decode.Decoder Literal
decodeLiteral =
    Decode.index 0 Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "BoolLiteral" ->
                        Decode.map BoolLiteral
                            (Decode.index 1 Decode.bool)

                    "CharLiteral" ->
                        Decode.map CharLiteral
                            (Decode.index 1 Decode.string
                                |> Decode.andThen
                                    (\str ->
                                        case String.uncons str of
                                            Just ( ch, _ ) ->
                                                Decode.succeed ch

                                            Nothing ->
                                                Decode.fail "Single char expected"
                                    )
                            )

                    "StringLiteral" ->
                        Decode.map StringLiteral
                            (Decode.index 1 Decode.string)

                    "IntLiteral" ->
                        Decode.map IntLiteral
                            (Decode.index 1 Decode.int)

                    "FloatLiteral" ->
                        Decode.map FloatLiteral
                            (Decode.index 1 Decode.float)

                    other ->
                        Decode.fail <| "Unknown literal type: " ++ other
            )
