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
    filterDecorations decorationId (always << always True) allDecorationConfigData


{-| Given a decoration type and value, get every node decorated with that value
-}
getNodeIdsDecoratedWithValue : DecorationID -> RawValue -> AllDecorationConfigAndData -> List NodeID
getNodeIdsDecoratedWithValue decorationId decorationValue allDecorationConfigData =
    filterDecorations decorationId (\_ v -> v == decorationValue) allDecorationConfigData

{-| Given a decoration type and a predicate, return a List of NodeIDs where the decoration satisfies the predicate
-}
filterDecorations : DecorationID -> (DecorationID -> RawValue -> Bool) -> AllDecorationConfigAndData -> List NodeID
filterDecorations decorationId filterFunction allDecorationConfigData =
    allDecorationConfigData
        |> Dict.get decorationId
        |> Maybe.map (\decorationsConfigData -> SDKDict.filter filterFunction decorationsConfigData.data)
        |> Maybe.map SDKDict.keys
        |> Maybe.withDefault []
