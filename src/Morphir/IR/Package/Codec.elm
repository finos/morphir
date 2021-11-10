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


module Morphir.IR.Package.Codec exposing
    ( encodeSpecification, decodeSpecification
    , encodeDefinition, decodeDefinition
    )

{-| Codecs for types in the `Morphir.IR.Package` module.


# Specification

@docs encodeSpecification, decodeSpecification


# Definition

@docs encodeDefinition, decodeDefinition

-}

import Dict
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.AccessControlled.Codec exposing (decodeAccessControlled, encodeAccessControlled)
import Morphir.IR.Module.Codec as ModuleCodec
import Morphir.IR.Package exposing (Definition, Specification)
import Morphir.IR.Path.CodecV1 exposing (decodePath, encodePath)


{-| Encode Specification.
-}
encodeSpecification : (ta -> Encode.Value) -> Specification ta -> Encode.Value
encodeSpecification encodeTypeAttributes spec =
    Encode.object
        [ ( "modules"
          , spec.modules
                |> Dict.toList
                |> Encode.list
                    (\( moduleName, moduleSpec ) ->
                        Encode.list identity
                            [ encodePath moduleName
                            , ModuleCodec.encodeSpecification encodeTypeAttributes moduleSpec
                            ]
                    )
          )
        ]


{-| Decode Specification.
-}
decodeSpecification : Decode.Decoder ta -> Decode.Decoder (Specification ta)
decodeSpecification decodeAttributes =
    Decode.map Specification
        (Decode.field "modules"
            (Decode.map Dict.fromList
                (Decode.list
                    (Decode.map2 Tuple.pair
                        (Decode.index 0 decodePath)
                        (Decode.index 1 (ModuleCodec.decodeSpecification decodeAttributes))
                    )
                )
            )
        )


{-| Encode Definition.
-}
encodeDefinition : (ta -> Encode.Value) -> (va -> Encode.Value) -> Definition ta va -> Encode.Value
encodeDefinition encodeTypeAttributes encodeValueAttributes def =
    Encode.object
        [ ( "modules"
          , def.modules
                |> Dict.toList
                |> Encode.list
                    (\( moduleName, moduleDef ) ->
                        Encode.list identity
                            [ encodePath moduleName
                            , encodeAccessControlled (ModuleCodec.encodeDefinition encodeTypeAttributes encodeValueAttributes) moduleDef
                            ]
                    )
          )
        ]


{-| Decode Definition.
-}
decodeDefinition : Decode.Decoder ta -> Decode.Decoder va -> Decode.Decoder (Definition ta va)
decodeDefinition decodeAttributes decodeAttributes2 =
    Decode.map Definition
        (Decode.field "modules"
            (Decode.map Dict.fromList
                (Decode.list
                    (Decode.map2 Tuple.pair
                        (Decode.index 0 decodePath)
                        (Decode.index 1 (decodeAccessControlled (ModuleCodec.decodeDefinition decodeAttributes decodeAttributes2)))
                    )
                )
            )
        )
