module Morphir.CustomAttribute.Codec exposing (..)

import Dict exposing (Dict)
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.CustomAttribute.CustomAttribute exposing (CustomAttributeConfig, CustomAttributeDetail,  CustomAttributeInfo)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.Distribution.Codec exposing (decodeVersionedDistribution)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.FQName.CodecV1 as FQName
import Morphir.IR.NodeId exposing (NodeID(..), nodeIdFromString, nodeIdToString)
import Morphir.IR.Type as Type
import Morphir.IR.Type.DataCodec as DataCodec
import Morphir.IR.Value as IRValue
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
                                        case message of
                                            Morphir.IR.NodeId.InvalidNodeID msg->
                                                Decode.fail ("Invalid NodeID : " ++ msg)

                                            Morphir.IR.NodeId.InvalidPath msg ->
                                                Decode.fail ("Invalid Nodepath : " ++ msg)
                            )
                )
                (Decode.succeed [])
            )
        |> Decode.map SDKDict.fromList


decodeAttributes : Decode.Decoder CustomAttributeInfo
decodeAttributes =
    Decode.dict decodeCustomAttributeDetail


valueDecoder : Distribution -> FQName -> Decode.Decoder IRValue.RawValue
valueDecoder distro entryPointFqn =
    let
        resultToFailure result =
            case result of
                Ok decoder ->
                    decoder

                Err error ->
                    Decode.fail error
    in
    DataCodec.decodeData (IR.fromDistribution distro) (Type.Reference () entryPointFqn [])
        |> resultToFailure


decodeCustomAttributeData : Distribution -> FQName -> Decode.Decoder (SDKDict.Dict NodeID (IRValue.Value () ()))
decodeCustomAttributeData distro entryPointFqn =
    Decode.keyValuePairs (valueDecoder distro entryPointFqn)
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
                                        case message of
                                            Morphir.IR.NodeId.InvalidNodeID msg->
                                                Decode.fail ("Invalid NodeID : " ++ msg)

                                            Morphir.IR.NodeId.InvalidPath msg ->
                                                Decode.fail ("Invalid Nodepath : " ++ msg)
                            )
                )
                (Decode.succeed [])
            )
        |> Decode.map SDKDict.fromList


decodeCustomAttributeDetail : Decode.Decoder CustomAttributeDetail
decodeCustomAttributeDetail =
    let
        entryPointDecoder =
            Decode.field "entryPoint" Decode.string
                |> Decode.map (\fqnString -> FQName.fromString fqnString ":")
    in
    Decode.map3
        (\displayName entryPoint distribution ->
            Decode.field "data" (decodeCustomAttributeData distribution entryPoint)
                |> Decode.map (CustomAttributeDetail displayName entryPoint distribution)
        )
        (Decode.field "displayName" Decode.string)
        entryPointDecoder
        (Decode.field "iR" decodeVersionedDistribution)
        |> Decode.andThen identity


encodeAttributeData : CustomAttributeDetail -> Encode.Value
encodeAttributeData customAttrDetail =
    let
        encodeIrValue =
            customAttrDetail.data
                |> SDKDict.toList
                |> List.map
                    (\( nodeId, irValue ) ->
                        let
                            resultToFailure result =
                                case result of
                                    Ok encoder ->
                                        encoder

                                    Err error ->
                                        Encode.null
                        in
                        ( nodeIdToString nodeId
                        , DataCodec.encodeData
                            (IR.fromDistribution customAttrDetail.iR)
                            (Type.Reference () customAttrDetail.entryPoint [])
                            |> Result.andThen
                                (\encoderValue ->
                                    irValue |> encoderValue
                                )
                            |> resultToFailure
                        )
                    )
    in
    Encode.object encodeIrValue
