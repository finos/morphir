module Morphir.CustomAttribute.Codec exposing (..)

import Dict exposing (Dict)
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.CustomAttribute.CustomAttribute exposing (CustomAttributeConfig, CustomAttributeDetail, CustomAttributeId, CustomAttributeInfo, CustomAttributeValueByNodeID, CustomAttributes)
import Morphir.IR as IR
import Morphir.IR.Distribution.Codec exposing (decodeVersionedDistribution)
import Morphir.IR.FQName.Codec as FQN
import Morphir.IR.NodeId exposing (NodeID(..), nodeIdFromString)
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
                                        Decode.fail message
                            )
                )
                (Decode.succeed [])
            )
        |> Decode.map SDKDict.fromList


decodeAttributes : Decode.Decoder CustomAttributeInfo
decodeAttributes =
    Decode.dict decodeCustomAttributeDetail


decodeCustomAttributeDetail : Decode.Decoder CustomAttributeDetail
decodeCustomAttributeDetail =
    let
        irDecoder =
            Decode.field "ir" decodeVersionedDistribution

        entryPointDecoder =
            Decode.field "entryPoint" FQN.decodeFQName

        valueDecoder : Decode.Decoder IRValue.RawValue
        valueDecoder =
            irDecoder
                |> Decode.andThen
                    (\ir ->
                        entryPointDecoder
                            |> Decode.andThen
                                (\entryPointFqn ->
                                    DataCodec.decodeData (IR.fromDistribution ir) (Type.Reference () entryPointFqn [])
                                        |> resultToFailure
                                )
                    )

        resultToFailure result =
            case result of
                Ok decoder ->
                    decoder

                Err error ->
                    Decode.fail error

        decodeCustomAttributeData : Decode.Decoder (SDKDict.Dict NodeID (IRValue.Value () ()))
        decodeCustomAttributeData =
            Decode.keyValuePairs valueDecoder
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
    in
    Decode.map4 CustomAttributeDetail
        (Decode.field "displayName" Decode.string)
        entryPointDecoder
        irDecoder
        (Decode.field "data" decodeCustomAttributeData)
