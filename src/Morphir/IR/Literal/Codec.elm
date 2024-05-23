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


module Morphir.IR.Literal.Codec exposing (..)

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

        WholeNumberLiteral v ->
            Encode.list identity
                [ Encode.string "WholeNumberLiteral"
                , Encode.int v
                ]

        FloatLiteral v ->
            Encode.list identity
                [ Encode.string "FloatLiteral"
                , Encode.float v
                ]

        DecimalLiteral v ->
            Encode.list identity
                [ Encode.string "DecimalLiteral"
                , Encode.string (Decimal.toString v)
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

                    "WholeNumberLiteral" ->
                        Decode.map WholeNumberLiteral
                            (Decode.index 1 Decode.int)

                    "FloatLiteral" ->
                        Decode.map FloatLiteral
                            (Decode.index 1 Decode.float)

                    "DecimalLiteral" ->
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
