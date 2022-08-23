module Morphir.CustomAttribute.Codec exposing (..)
import Morphir.CustomAttribute.CustomAttribute exposing (CustomAttributeConfig)
import Json.Encode as Encode
import Json.Decode as Decode
import Morphir.IR.Type.Codec exposing (encodeType)
import Morphir.Codec exposing (encodeUnit, decodeUnit)
import Morphir.IR.Type.Codec exposing (decodeType)


encodeCustomAttributeConfig : CustomAttributeConfig -> Encode.Value
encodeCustomAttributeConfig customAttributeConfig = 
     Encode.object
        [ ( "attributeName", Encode.string customAttributeConfig.attributeName )
        , ( "filePath", Encode.string customAttributeConfig.filePath )
        , ( "type", encodeType encodeUnit customAttributeConfig.type)
        ]

decodeCustomAttributeConfig : Decode.Decoder CustomAttributeConfig
decodeCustomAttributeConfig  =
    Decode.map3 CustomAttributeConfig
        (Decode.field "attributeName" Decode.string)
        (Decode.field "filePath" Decode.string)
        (Decode.field "type" (decodeType decodeUnit))