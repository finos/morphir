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


module Morphir.IR.Name.Codec exposing (..)

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.Name as Name exposing (Name)


{-| Encode a name to JSON.
-}
encodeName : Name -> Encode.Value
encodeName name =
    name
        |> Name.toList
        |> Encode.list Encode.string


{-| Decode a name from JSON.
-}
decodeName : Decode.Decoder Name
decodeName =
    Decode.list Decode.string
        |> Decode.map Name.fromList
