module Morphir.CustomAttribute.CustomAttribute exposing (..)
import Morphir.Compiler exposing (FilePath)
import Dict exposing (Dict)
import Json.Encode as Encode
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.NodeId exposing (NodeID)


type alias CustomAttributeId 
	= String

type alias CustomAttributeConfig =
	{ filePath : FilePath
	}

type alias CustomAttributeConfigs =
	Dict CustomAttributeId CustomAttributeConfig

type alias CustomAttributeValues =
	Dict NodeID Encode.Value

type alias CustomAttribute =
    Dict FQName (Dict String Encode.Value)