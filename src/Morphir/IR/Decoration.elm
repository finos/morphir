module Morphir.IR.Decoration exposing (..)

import Dict exposing (Dict)
import Morphir.IR.Distribution
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.NodeId exposing (NodeID)
import Morphir.IR.Value exposing (RawValue)
import Morphir.SDK.Dict as SDKDict


type alias DecorationID =
    String


type alias AllDecorationConfigAndData =
    Dict DecorationID DecorationConfigAndData


type alias DecorationData =
    SDKDict.Dict NodeID RawValue


type alias DecorationConfigAndData =
    { displayName : String
    , entryPoint : FQName
    , iR : Morphir.IR.Distribution.Distribution
    , data : DecorationData
    }


{-| Get every nodeId decorated with a given decoration
-}
getDecoratedNodeIds : DecorationID -> AllDecorationConfigAndData -> List NodeID
getDecoratedNodeIds decorationId allDecorationConfigData =
    allDecorationConfigData
        |> Dict.get decorationId
        |> Maybe.map (\decorationsConfigData -> SDKDict.keys decorationsConfigData.data)
        |> Maybe.withDefault []
