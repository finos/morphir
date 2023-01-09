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


module Morphir.IR.Module.Codec exposing (..)

{-| -}

import Dict
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.AccessControlled.Codec exposing (decodeAccessControlled, encodeAccessControlled)
import Morphir.IR.Documented.Codec exposing (decodeDocumented, encodeDocumented)
import Morphir.IR.Module exposing (Definition, Specification)
import Morphir.IR.Name.Codec exposing (decodeName, encodeName)
import Morphir.IR.Type.Codec as TypeCodec
import Morphir.IR.Value.Codec as ValueCodec


{-| -}
encodeSpecification : (ta -> Encode.Value) -> Specification ta -> Encode.Value
encodeSpecification encodeTypeAttributes spec =
    Encode.object
        [ ( "types"
          , spec.types
                |> Dict.toList
                |> Encode.list
                    (\( name, typeSpec ) ->
                        Encode.list identity
                            [ encodeName name
                            , typeSpec |> encodeDocumented (TypeCodec.encodeSpecification encodeTypeAttributes)
                            ]
                    )
          )
        , ( "values"
          , spec.values
                |> Dict.toList
                |> Encode.list
                    (\( name, valueSpec ) ->
                        Encode.list identity
                            [ encodeName name
                            , valueSpec |> encodeDocumented (ValueCodec.encodeSpecification encodeTypeAttributes)
                            ]
                    )
          )
        , ("doc", 
            spec.doc |> Maybe.map Encode.string |> Maybe.withDefault Encode.null)
        ]


decodeSpecification : Decode.Decoder ta -> Decode.Decoder (Specification ta)
decodeSpecification decodeTypeAttributes =
    Decode.map3 Specification
        (Decode.field "types"
            (Decode.map Dict.fromList
                (Decode.list
                    (Decode.map2 Tuple.pair
                        (Decode.index 0 decodeName)
                        (Decode.index 1 (decodeDocumented (TypeCodec.decodeSpecification decodeTypeAttributes)))
                    )
                )
            )
        )
        (Decode.field "values"
            (Decode.map Dict.fromList
                (Decode.list
                    (Decode.map2 Tuple.pair
                        (Decode.index 0 decodeName)
                        (Decode.index 1 (decodeDocumented (ValueCodec.decodeSpecification decodeTypeAttributes)))
                    )
                )
            )
        )
        (Decode.oneOf [(Decode.field "doc" (Decode.maybe Decode.string)), Decode.succeed Nothing ])


encodeDefinition : (ta -> Encode.Value) -> (va -> Encode.Value) -> Definition ta va -> Encode.Value
encodeDefinition encodeTypeAttributes encodeValueAttributes def =
    Encode.object
        [ ( "types"
          , def.types
                |> Dict.toList
                |> Encode.list
                    (\( name, typeDef ) ->
                        Encode.list identity
                            [ encodeName name
                            , typeDef |> encodeAccessControlled (encodeDocumented (TypeCodec.encodeDefinition encodeTypeAttributes))
                            ]
                    )
          )
        , ( "values"
          , def.values
                |> Dict.toList
                |> Encode.list
                    (\( name, valueDef ) ->
                        Encode.list identity
                            [ encodeName name
                            , valueDef |> encodeAccessControlled (encodeDocumented (ValueCodec.encodeDefinition encodeTypeAttributes encodeValueAttributes))
                            ]
                    )
          )
         , ("doc", 
            def.doc |> Maybe.map Encode.string |> Maybe.withDefault Encode.null)
        ]


decodeDefinition : Decode.Decoder ta -> Decode.Decoder va -> Decode.Decoder (Definition ta va)
decodeDefinition decodeTypeAttributes decodeValueAttributes =
    Decode.map3 Definition
        (Decode.field "types"
            (Decode.map Dict.fromList
                (Decode.list
                    (Decode.map2 Tuple.pair
                        (Decode.index 0 decodeName)
                        (Decode.index 1 (decodeAccessControlled (decodeDocumented (TypeCodec.decodeDefinition decodeTypeAttributes))))
                    )
                )
            )
        )
        (Decode.field "values"
            (Decode.map Dict.fromList
                (Decode.list
                    (Decode.map2 Tuple.pair
                        (Decode.index 0 decodeName)
                        (Decode.index 1 (decodeAccessControlled (decodeDocumented (ValueCodec.decodeDefinition decodeTypeAttributes decodeValueAttributes))))
                    )
                )
            )
        )
    (Decode.oneOf [(Decode.field "doc" (Decode.maybe Decode.string)), Decode.succeed Nothing ])
