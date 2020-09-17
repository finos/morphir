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


module Morphir.IR.Distribution.Codec exposing (..)

import Dict
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Package.Codec as PackageCodec
import Morphir.IR.Path.Codec exposing (decodePath, encodePath)


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
                                , PackageCodec.encodeSpecification (\_ -> Encode.object []) packageSpec
                                ]
                        )
                , PackageCodec.encodeDefinition (\_ -> Encode.object []) (\_ -> Encode.object []) def
                ]


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
                                            (Decode.index 1 (PackageCodec.decodeSpecification (Decode.succeed ())))
                                        )
                                    )
                                )
                            )
                            (Decode.index 3 (PackageCodec.decodeDefinition (Decode.succeed ()) (Decode.succeed ())))

                    other ->
                        Decode.fail <| "Unknown value type: " ++ other
            )
