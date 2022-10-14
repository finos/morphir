module Morphir.CustomAttribute.CustomAttribute exposing (..)

import Dict exposing (Dict)
import Json.Encode as Encode
import Morphir.Compiler exposing (FilePath)
import Morphir.IR.Distribution
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.NodeId exposing (NodeID)
import Morphir.IR.Value as IRValue
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
    SDKDict.Dict NodeID (Dict CustomAttributeId NodeAttributeDetail)


type alias CustomAttributes =
    Dict CustomAttributeId CustomAttributeValueByNodeID


type alias CustomAttributeInfo =
    Dict CustomAttributeId CustomAttributeDetail


type alias CustomAttributeDetail =
    { displayName : String
    , entryPoint : FQName
    , iR : Morphir.IR.Distribution.Distribution
    , data : SDKDict.Dict NodeID (IRValue.Value () ())
    }


type alias NodeAttributeDetail =
    { displayName : String
    , iR : Morphir.IR.Distribution.Distribution
    , entryPoint : FQName
    , value : IRValue.Value () ()
    }


toAttributeValueByNodeId : CustomAttributeInfo -> CustomAttributeValuesByNodeID
toAttributeValueByNodeId customAttributeInfo =
    customAttributeInfo
        |> Dict.foldl
            (\customAttrId customAttrValueDict customAttrByNodeIdDict ->
                customAttrValueDict.data
                    |> SDKDict.foldl
                        (\nodeId irValue innerValueByNodeId ->
                            let
                                nodeDetail : NodeAttributeDetail
                                nodeDetail =
                                    { displayName = customAttrValueDict.displayName
                                    , iR = customAttrValueDict.iR
                                    , entryPoint = customAttrValueDict.entryPoint
                                    , value = irValue
                                    }
                            in
                            if SDKDict.member nodeId innerValueByNodeId then
                                SDKDict.update nodeId (Maybe.map (Dict.insert customAttrId nodeDetail)) innerValueByNodeId

                            else
                                SDKDict.insert nodeId (Dict.singleton customAttrId nodeDetail) innerValueByNodeId
                        )
                        customAttrByNodeIdDict
            )
            SDKDict.empty
