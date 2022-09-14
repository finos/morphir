module Morphir.CustomAttribute.Codec exposing (..)

import Dict exposing (Dict)
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.CustomAttribute.CustomAttribute exposing (CustomAttributeConfig, CustomAttributeId, CustomAttributeValuesByNodeID)
import Morphir.IR exposing (IR)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.NodeId exposing (NodeID(..))
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


decodeAttributes : Decode.Decoder CustomAttributeValuesByNodeID
decodeAttributes =
    Decode.map
        (\pairs ->
            pairs
                |> List.foldl
                    (\( attrId, nodeIdByValueList ) customAttrByNodeIdDictResult ->
                        nodeIdByValueList
                            |> List.foldl
                                (\( nodeIdResult, jsonValue ) innerCustomAttrByNodeIdResult ->
                                    Result.map2
                                        (\innerCustomAttrByNodeId nodeId ->
                                            if SDKDict.member nodeId innerCustomAttrByNodeId then
                                                SDKDict.update nodeId (Maybe.map (Dict.insert attrId jsonValue)) innerCustomAttrByNodeId

                                            else
                                                SDKDict.insert nodeId (Dict.singleton attrId jsonValue) innerCustomAttrByNodeId
                                        )
                                        innerCustomAttrByNodeIdResult
                                        nodeIdResult
                                )
                                customAttrByNodeIdDictResult
                    )
                    (Ok SDKDict.empty)
        )
        decodeOuterStruct
        |> Decode.andThen
            (\decodeResult ->
                case decodeResult of
                    Ok customAttrByNodeId ->
                        Decode.succeed customAttrByNodeId

                    Err message ->
                        Decode.fail message
            )


decodeOuterStruct : Decode.Decoder (List ( String, List ( Result String NodeID, Decode.Value ) ))
decodeOuterStruct =
    Decode.keyValuePairs decodeNodeIDByValuePairs


decodeNodeIDByValuePairs : Decode.Decoder (List ( Result String NodeID, Decode.Value ))
decodeNodeIDByValuePairs =
    Decode.keyValuePairs Decode.value
        |> Decode.map (List.map (Tuple.mapFirst nodeIdFromString))


nodeIdFromString : String -> Result String NodeID
nodeIdFromString str =
    case String.split ":" str of
        nodeType :: packageName :: moduleName :: localName :: [] ->
            case ( nodeType, FQName.fqn packageName moduleName localName ) of
                ( "Type", fqn ) ->
                    Ok <| TypeID fqn

                ( "Value", fqn ) ->
                    Ok <| ValueID fqn

                _ ->
                    Err <| "Unknown Node type: " ++ nodeType

        _ ->
            Err <| "Invalid NodeId: " ++ str
