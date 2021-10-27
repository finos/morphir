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


module Morphir.IR.AccessControlled.Codec exposing (..)

{-| Encode AccessControlled to JSON.
-}

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)


encodeAccess : Access -> Encode.Value
encodeAccess access =
    case access of
        Public ->
            Encode.string "Public"

        Private ->
            Encode.string "Private"


encodeAccessControlled : (a -> Encode.Value) -> AccessControlled a -> Encode.Value
encodeAccessControlled encodeValue ac =
    Encode.object
        [ ( "access" , encodeAccess ac.access )
        , ( "value" , encodeValue ac.value )
        ]


decodeAccess : Decode.Decoder String -> Decode.Decoder Access
decodeAccess =
    Decode.andThen
        (\str ->
            case str of
                "Public" ->
                    Decode.succeed Public

                "Private" ->
                    Decode.succeed Private

                other ->
                    Decode.fail <| "Unknown access controlled type: " ++ other
        )


{-| Decode AccessControlled from JSON.
-}
decodeAccessControlled : Decode.Decoder a -> Decode.Decoder (AccessControlled a)
decodeAccessControlled decodeValue =
    Decode.map2 AccessControlled
        (Decode.field "access" Decode.string |> decodeAccess)
        (Decode.field "value" decodeValue)
