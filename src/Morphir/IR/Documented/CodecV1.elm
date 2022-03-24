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


module Morphir.IR.Documented.CodecV1 exposing (..)

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.Documented exposing (Documented)


encodeDocumented : (a -> Encode.Value) -> Documented a -> Encode.Value
encodeDocumented encodeValue d =
    Encode.list identity
        [ Encode.string d.doc
        , encodeValue d.value
        ]


decodeDocumented : Decode.Decoder a -> Decode.Decoder (Documented a)
decodeDocumented decodeValue =
    Decode.oneOf
    [( Decode.map2 Documented
        (Decode.index 0 Decode.string)
        (Decode.index 1 decodeValue))
    , ( Decode.map (Documented "")
        (decodeValue))
    ]