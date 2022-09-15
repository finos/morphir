module Morphir.CustomAttribute.Codec exposing (..)

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.CustomAttribute.CustomAttribute exposing (CustomAttributeConfig, CustomAttributeId, CustomAttributeValueByNodeID, CustomAttributes)
import Morphir.IR.NodeId exposing (NodeID(..), nodeIdFromString)
import Morphir.SDK.Dict as SDKDict


encodeCustomAttributeConfig : CustomAttributeConfig -> Encode.Value
encodeCustomAttributeConfig customAttributeConfig =
    Encode.object
        [ ( "filePath", Encode.string customAttributeConfig.filePath )
        ]


decodeCustomAttributeConfig : Decode.Decoder CustomAttributeConfig
decodeCustomAttributeConfig =
    Decode.map CustomAttributeConfig
        (Decode.field "filePath" Decode.string)


decodeNodeIDByValuePairs : Decode.Decoder (List ( NodeID, Decode.Value ))
decodeNodeIDByValuePairs =
    Decode.keyValuePairs Decode.value
        |> Decode.map (List.map (Tuple.mapFirst nodeIdFromString))


decodeAttributes : Decode.Decoder CustomAttributes
decodeAttributes =
    Decode.dict
        (decodeNodeIDByValuePairs
            |> Decode.map SDKDict.fromList
        )
