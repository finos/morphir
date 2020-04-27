module Morphir.IR.FQName.Codec exposing (..)

{-| Encode a fully-qualified name to JSON.
-}

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Name.Codec exposing (decodeName, encodeName)
import Morphir.IR.Path.Codec exposing (decodePath, encodePath)


encodeFQName : FQName -> Encode.Value
encodeFQName (FQName packagePath modulePath localName) =
    Encode.list identity
        [ packagePath |> encodePath
        , modulePath |> encodePath
        , localName |> encodeName
        ]


{-| Decode a fully-qualified name from JSON.
-}
decodeFQName : Decode.Decoder FQName
decodeFQName =
    Decode.map3 FQName
        (Decode.index 0 decodePath)
        (Decode.index 1 decodePath)
        (Decode.index 2 decodeName)
