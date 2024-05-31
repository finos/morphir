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


module Morphir.File.FileMap.Codec exposing (encodeFileMap)

{-| Codecs for types in the `Morphir.File.FileMap` module.


# FileMap

@docs encodeFileMap

-}

import Dict
import Json.Encode as Encode
import Morphir.File.FileMap exposing (FileMap)


{-| Encode FileMap.
-}
encodeFileMap : FileMap -> Encode.Value
encodeFileMap fileMap =
    fileMap
        |> Dict.toList
        |> Encode.list
            (\( ( dirPath, fileName ), content ) ->
                Encode.list identity
                    [ Encode.list identity
                        [ Encode.list Encode.string dirPath
                        , Encode.string fileName
                        ]
                    , Encode.string content
                    ]
            )
