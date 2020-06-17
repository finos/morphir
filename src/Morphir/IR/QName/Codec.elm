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
