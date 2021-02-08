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


module Morphir.IR.FQName.Codec exposing (..)

{-| Encode a fully-qualified name to JSON.
-}

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.FQName exposing (FQName, fQName)
import Morphir.IR.Name.Codec exposing (decodeName, encodeName)
import Morphir.IR.Path.Codec exposing (decodePath, encodePath)


encodeFQName : FQName -> Encode.Value
encodeFQName ( packagePath, modulePath, localName ) =
    Encode.list identity
        [ packagePath |> encodePath
        , modulePath |> encodePath
        , localName |> encodeName
        ]


{-| Decode a fully-qualified name from JSON.
-}
decodeFQName : Decode.Decoder FQName
decodeFQName =
    Decode.map3 fQName
        (Decode.index 0 decodePath)
        (Decode.index 1 decodePath)
        (Decode.index 2 decodeName)
