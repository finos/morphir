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


module Morphir.IR.Distribution.CodecV1 exposing (encodeDistribution, decodeDistribution)

{-| Codecs for types in the `Morphir.IR.Distribution` module.


# Distribution

@docs encodeVersionedDistribution, decodeVersionedDistribution, encodeDistribution, decodeDistribution

-}

import Dict
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.Codec exposing (decodeUnit, encodeUnit)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Package.CodecV1 as PackageCodec
import Morphir.IR.Path.CodecV1 exposing (decodePath, encodePath)
import Morphir.IR.Type.CodecV1 exposing (decodeType, encodeType)


{-| Encode Distribution.
-}
encodeDistribution : Distribution -> Encode.Value
encodeDistribution distro =
    case distro of
        Library packagePath dependencies def ->
            Encode.list identity
                [ Encode.string "library"
                , encodePath packagePath
                , dependencies
                    |> Dict.toList
                    |> Encode.list
                        (\( packageName, packageSpec ) ->
                            Encode.list identity
                                [ encodePath packageName
                                , PackageCodec.encodeSpecification encodeUnit packageSpec
                                ]
                        )
                , def
                    |> PackageCodec.encodeDefinition encodeUnit
                        (encodeType encodeUnit)
                ]


{-| Decode Distribution.
-}
decodeDistribution : Decode.Decoder Distribution
decodeDistribution =
    Decode.index 0 Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "library" ->
                        Decode.map3 Library
                            (Decode.index 1 decodePath)
                            (Decode.index 2
                                (Decode.map Dict.fromList
                                    (Decode.list
                                        (Decode.map2 Tuple.pair
                                            (Decode.index 0 decodePath)
                                            (Decode.index 1 (PackageCodec.decodeSpecification decodeUnit))
                                        )
                                    )
                                )
                            )
                            (Decode.index 3 (PackageCodec.decodeDefinition decodeUnit (decodeType decodeUnit)))

                    other ->
                        Decode.fail <| "Unknown value type: " ++ other
            )
