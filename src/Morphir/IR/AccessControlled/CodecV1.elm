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


module Morphir.IR.AccessControlled.CodecV1 exposing (..)

{-| Encode AccessControlled to JSON.
-}

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)


encodeAccessControlled : (a -> Encode.Value) -> AccessControlled a -> Encode.Value
encodeAccessControlled encodeValue ac =
    case ac.access of
        Public ->
            Encode.list identity
                [ Encode.string "public"
                , encodeValue ac.value
                ]

        Private ->
            Encode.list identity
                [ Encode.string "private"
                , encodeValue ac.value
                ]


{-| Decode AccessControlled from JSON.
-}
decodeAccessControlled : Decode.Decoder a -> Decode.Decoder (AccessControlled a)
decodeAccessControlled decodeValue =
    Decode.index 0 Decode.string
        |> Decode.andThen
            (\tag ->
                case tag of
                    "public" ->
                        Decode.map (AccessControlled Public)
                            (Decode.index 1 decodeValue)

                    "private" ->
                        Decode.map (AccessControlled Private)
                            (Decode.index 1 decodeValue)

                    other ->
                        Decode.fail <| "Unknown access controlled type: " ++ other
            )
