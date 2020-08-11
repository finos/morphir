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
encodeSpecification : (a -> Encode.Value) -> Specification a -> Encode.Value
encodeSpecification encodeAttributes spec =
    Encode.object
        [ ( "types"
          , spec.types
                |> Dict.toList
                |> Encode.list
                    (\( name, typeSpec ) ->
                        Encode.list identity
                            [ encodeName name
                            , typeSpec |> encodeDocumented (TypeCodec.encodeSpecification encodeAttributes)
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
                            , valueSpec |> ValueCodec.encodeSpecification encodeAttributes
                            ]
                    )
          )
        ]


encodeDefinition : (a -> Encode.Value) -> Definition a -> Encode.Value
encodeDefinition encodeAttributes def =
    Encode.object
        [ ( "types"
          , def.types
                |> Dict.toList
                |> Encode.list
                    (\( name, typeDef ) ->
                        Encode.list identity
                            [ encodeName name
                            , typeDef |> encodeAccessControlled (encodeDocumented (TypeCodec.encodeDefinition encodeAttributes))
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
                            , valueDef |> encodeAccessControlled (ValueCodec.encodeDefinition encodeAttributes)
                            ]
                    )
          )
        ]


decodeDefinition : Decode.Decoder a -> Decode.Decoder (Definition a)
decodeDefinition decodeAttributes =
    Decode.map2 Definition
        (Decode.field "types"
            (Decode.map Dict.fromList
                (Decode.list
                    (Decode.map2 Tuple.pair
                        (Decode.index 0 decodeName)
                        (Decode.index 1 (decodeAccessControlled (decodeDocumented (TypeCodec.decodeDefinition decodeAttributes))))
                    )
                )
            )
        )
        (Decode.field "values"
            (Decode.map Dict.fromList
                (Decode.list
                    (Decode.map2 Tuple.pair
                        (Decode.index 0 decodeName)
                        (Decode.index 1 (decodeAccessControlled (ValueCodec.decodeDefinition decodeAttributes)))
                    )
                )
            )
        )
