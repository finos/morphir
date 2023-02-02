module Morphir.CustomAttribute.CustomAttribute exposing (..)

import Dict exposing (Dict)
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



type alias CustomAttributeInfo =
    Dict CustomAttributeId CustomAttributeDetail


type alias CustomAttributeDetail =
    { displayName : String
    , entryPoint : FQName
    , iR : Morphir.IR.Distribution.Distribution
    , data : SDKDict.Dict NodeID (IRValue.Value () ())
    }
