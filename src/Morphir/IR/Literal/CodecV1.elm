{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}


module Morphir.IR.Literal.CodecV1 exposing (..)

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.SDK.Decimal as Decimal
import Morphir.SDK.UUID as UUID


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

        WholeNumberLiteral v ->
            Encode.list identity
                [ Encode.string "int_literal"
                , Encode.int v
                ]

        FloatLiteral v ->
            Encode.list identity
                [ Encode.string "float_literal"
                , Encode.float v
                ]

        DecimalLiteral v ->
            Encode.list identity
                [ Encode.string "decimal_literal"
                , Encode.string (Decimal.toString v)
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
                        Decode.map WholeNumberLiteral
                            (Decode.index 1 Decode.int)

                    "float_literal" ->
                        Decode.map FloatLiteral
                            (Decode.index 1 Decode.float)

                    "decimal_literal" ->
                        Decode.map DecimalLiteral
                            (Decode.index 1 Decode.string
                                |> Decode.andThen
                                    (\str ->
                                        case Decimal.fromString str of
                                            Just decimal ->
                                                Decode.succeed decimal

                                            Nothing ->
                                                "Failed to create decimal value from string: "
                                                    ++ str
                                                    |> Decode.fail
                                    )
                            )

                    other ->
                        Decode.fail <| "Unknown literal type: " ++ other
            )
