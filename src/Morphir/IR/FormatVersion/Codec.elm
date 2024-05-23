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


module Morphir.IR.FormatVersion.Codec exposing (encodeVersionedDistribution, decodeVersionedDistribution)

{-| Codecs provided for encoding and decoding a versioned distribution.


# VersionedDistribution

@docs encodeVersionedDistribution, decodeVersionedDistribution

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.Distribution.Codec exposing (decodeDistribution, encodeDistribution)
import Morphir.IR.Distribution.CodecV1 as CodecV1
import Morphir.IR.FormatVersion exposing (currentFormatVersion)


{-| Encode distribution including a version number.
-}
encodeVersionedDistribution : Distribution -> Encode.Value
encodeVersionedDistribution distro =
    Encode.object
        [ ( "formatVersion", Encode.int currentFormatVersion )
        , ( "distribution", encodeDistribution distro )
        ]


{-| Decode distribution including a version number.
-}
decodeVersionedDistribution : Decode.Decoder Distribution
decodeVersionedDistribution =
    Decode.oneOf
        [ Decode.field "formatVersion" Decode.int
            |> Decode.andThen
                (\formatVersion ->
                    if formatVersion == currentFormatVersion then
                        Decode.field "distribution" decodeDistribution

                    else if formatVersion == 1 then
                        Decode.field "distribution" CodecV1.decodeDistribution

                    else
                        Decode.fail
                            (String.concat
                                [ "The IR is using format version "
                                , String.fromInt formatVersion
                                , " but the latest format version is "
                                , String.fromInt currentFormatVersion
                                , ". Please regenerate it!"
                                ]
                            )
                )
        , Decode.fail "The IR is in an old format that doesn't have a format version on it. Please regenerate it!"
        ]
