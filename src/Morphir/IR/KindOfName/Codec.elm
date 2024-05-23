module Morphir.IR.KindOfName.Codec exposing (..)

import Json.Encode as Encode
import Morphir.IR.KindOfName exposing (KindOfName(..))


encodeKindOfName : KindOfName -> Encode.Value
encodeKindOfName kindOfName =
    case kindOfName of
        Type ->
            Encode.string "Type"

        Constructor ->
            Encode.string "Constructor"

        Value ->
            Encode.string "Value"
