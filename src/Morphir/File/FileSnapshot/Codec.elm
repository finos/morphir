module Morphir.File.FileSnapshot.Codec exposing (..)

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.File.FileSnapshot exposing (FileSnapshot)


decodeFileSnapshot : Decode.Decoder FileSnapshot
decodeFileSnapshot =
    Decode.dict Decode.string


encodeFileSnapshot : FileSnapshot -> Encode.Value
encodeFileSnapshot fileSnapshot =
    Encode.dict identity Encode.string fileSnapshot
