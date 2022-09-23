module Morphir.CustomAttribute.Codec exposing (..)

import Dict exposing (Dict)
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


decodeNodeIDByValuePairs : Decode.Decoder (SDKDict.Dict NodeID Decode.Value)
decodeNodeIDByValuePairs =
    Decode.keyValuePairs Decode.value
        |> Decode.andThen
            (List.foldl
                (\( nodeIdString, decodedValue ) decodedSoFar ->
                    decodedSoFar
                        |> Decode.andThen
                            (\nodeIdList ->
                                case nodeIdFromString nodeIdString of
                                    Ok nodeID ->
                                        Decode.succeed <| ( nodeID, decodedValue ) :: nodeIdList

                                    Err message ->
                                        Decode.fail message
                            )
                )
                (Decode.succeed [])
            )
        |> Decode.map SDKDict.fromList


decodeAttributes : Decode.Decoder CustomAttributes
decodeAttributes =
    Decode.dict decodeNodeIDByValuePairs
