module Morphir.IR.Path.Codec exposing (..)

{-| Encode a path to JSON.
-}

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.Name.Codec exposing (decodeName, encodeName)
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
