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


module Morphir.IR.QName.Codec exposing (..)

{-| Encode a qualified name to JSON.
-}

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.Name.Codec exposing (decodeName, encodeName)
import Morphir.IR.Path.Codec exposing (decodePath, encodePath)
import Morphir.IR.QName exposing (QName)


encodeQName : QName -> Encode.Value
encodeQName (QName modulePath localName) =
    Encode.list identity
        [ modulePath |> encodePath
        , localName |> encodeName
        ]


{-| Decode a qualified name from JSON.
-}
decodeQName : Decode.Decoder QName
decodeQName =
    Decode.map2 QName
        (Decode.index 0 decodePath)
        (Decode.index 1 decodeName)
