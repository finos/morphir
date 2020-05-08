module Morphir.IR.Literal.Codec exposing (..)

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.Literal exposing (Literal(..))


encodeLiteral : Literal -> Encode.Value
encodeLiteral l =
    case l of
        BoolLiteral v ->
            Encode.list identity
                [ Encode.string "bool_literal"
                , Encode.bool v
                ]

        CharLiteral v ->
            Encode.list identity
                [ Encode.string "char_literal"
                , Encode.string (String.fromChar v)
                ]

        StringLiteral v ->
            Encode.list identity
                [ Encode.string "string_literal"
                , Encode.string v
                ]

        IntLiteral v ->
            Encode.list identity
                [ Encode.string "int_literal"
                , Encode.int v
                ]

        FloatLiteral v ->
            Encode.list identity
                [ Encode.string "float_literal"
                , Encode.float v
                ]


decodeLiteral : Decode.Decoder Literal
decodeLiteral =
    Decode.index 0 Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "bool_literal" ->
                        Decode.map BoolLiteral
                            (Decode.index 1 Decode.bool)

                    "char_literal" ->
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

                    "string_literal" ->
                        Decode.map StringLiteral
                            (Decode.index 1 Decode.string)

                    "int_literal" ->
                        Decode.map IntLiteral
                            (Decode.index 1 Decode.int)

                    "float_literal" ->
                        Decode.map FloatLiteral
                            (Decode.index 1 Decode.float)

                    other ->
                        Decode.fail <| "Unknown literal type: " ++ other
            )
