module Morphir.CustomAttribute.CustomAttribute exposing (..)

import Dict exposing (Dict)
import Json.Encode as Encode
import Morphir.Compiler exposing (FilePath)
import Morphir.IR.NodeId exposing (NodeID)
import Morphir.SDK.Dict as SDKDict


type alias CustomAttributeId =
    String


type alias CustomAttributeConfig =
    { filePath : FilePath }


type alias CustomAttributeConfigs =
    Dict CustomAttributeId CustomAttributeConfig


type alias CustomAttributeValueByNodeID =
    SDKDict.Dict NodeID Encode.Value


type alias CustomAttributeValuesByNodeID =
    SDKDict.Dict NodeID (Dict CustomAttributeId Encode.Value)


type alias CustomAttributes =
    Dict CustomAttributeId CustomAttributeValueByNodeID


toAttributeValueByNodeId : CustomAttributes -> CustomAttributeValuesByNodeID
toAttributeValueByNodeId customAttributes =
    customAttributes
        |> Dict.foldl
            (\customAttrId customAttrValueDict customAttrByNodeIdDict ->
                customAttrValueDict
                    |> SDKDict.foldl
                        (\nodeId jsonValue innerValueByNodeId ->
                            if SDKDict.member nodeId innerValueByNodeId then
                                SDKDict.update nodeId (Maybe.map (Dict.insert customAttrId jsonValue)) innerValueByNodeId

                            else
                                SDKDict.insert nodeId (Dict.singleton customAttrId jsonValue) innerValueByNodeId
                        )
                        customAttrByNodeIdDict
            )
            SDKDict.empty
