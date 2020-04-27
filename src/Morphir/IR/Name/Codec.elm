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
