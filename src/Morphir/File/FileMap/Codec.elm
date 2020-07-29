module Morphir.File.FileMap.Codec exposing (..)

import Dict
import Json.Encode as Encode
import Morphir.File.FileMap exposing (FileMap)


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
