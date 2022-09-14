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
