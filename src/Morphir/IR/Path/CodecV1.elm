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


module Morphir.IR.Path.CodecV1 exposing (..)

{-| Encode a path to JSON.
-}

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.Name.CodecV1 exposing (decodeName, encodeName)
import Morphir.IR.Path as Path exposing (Path)


encodePath : Path -> Encode.Value
encodePath path =
    path
        |> Path.toList
        |> Encode.list encodeName


{-| Decode a path from JSON.
-}
decodePath : Decode.Decoder Path
decodePath =
    Decode.list decodeName
        |> Decode.map Path.fromList
