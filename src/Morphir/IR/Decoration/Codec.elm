module Morphir.IR.Decoration.Codec exposing
    ( decodeNodeIDByValuePairs, decodeAllDecorationConfigAndData
    , decodeDecorationValue, decodeDecorationData, decodeDecorationConfigAndData, encodeDecorationData
    )

{-| Codecs for types in the `Morphir.IR.Decoration` module

@docs decodeNodeIDByValuePairs, decodeAllDecorationConfigAndData
@docs decodeDecorationValue, decodeDecorationData, decodeDecorationConfigAndData, encodeDecorationData

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.Decoration exposing (AllDecorationConfigAndData, DecorationConfigAndData, DecorationData)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.FormatVersion.Codec exposing (decodeVersionedDistribution)
import Morphir.IR.NodeId exposing (NodeID(..), nodeIdFromString, nodeIdToString)
import Morphir.IR.Type as Type
import Morphir.IR.Type.DataCodec as DataCodec
import Morphir.IR.Value as IRValue
import Morphir.SDK.Dict as SDKDict


{-| -}
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
                                            Morphir.IR.NodeId.InvalidNodeID msg ->
                                                Decode.fail ("Invalid NodeID : " ++ msg)

                                            Morphir.IR.NodeId.InvalidPath msg ->
                                                Decode.fail ("Invalid Nodepath : " ++ msg)
                            )
                )
                (Decode.succeed [])
            )
        |> Decode.map SDKDict.fromList


{-| -}
decodeAllDecorationConfigAndData : Decode.Decoder AllDecorationConfigAndData
decodeAllDecorationConfigAndData =
    Decode.dict decodeDecorationConfigAndData


{-| -}
decodeDecorationValue : Distribution -> FQName -> Decode.Decoder IRValue.RawValue
decodeDecorationValue distro entryPointFqn =
    let
        resultToFailure result =
            case result of
                Ok decoder ->
                    decoder

                Err error ->
                    Decode.fail error
    in
    DataCodec.decodeData distro (Type.Reference () entryPointFqn [])
        |> resultToFailure


{-| -}
decodeDecorationData : Distribution -> FQName -> Decode.Decoder DecorationData
decodeDecorationData distro entryPointFqn =
    Decode.keyValuePairs (decodeDecorationValue distro entryPointFqn)
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
                                            Morphir.IR.NodeId.InvalidNodeID msg ->
                                                Decode.fail ("Invalid NodeID : " ++ msg)

                                            Morphir.IR.NodeId.InvalidPath msg ->
                                                Decode.fail ("Invalid Nodepath : " ++ msg)
                            )
                )
                (Decode.succeed [])
            )
        |> Decode.map SDKDict.fromList


{-| -}
decodeDecorationConfigAndData : Decode.Decoder DecorationConfigAndData
decodeDecorationConfigAndData =
    let
        entryPointDecoder =
            Decode.field "entryPoint" Decode.string
                |> Decode.andThen
                    (\fqnString ->
                        case FQName.fromStringStrict fqnString ":" of
                            Ok fqn ->
                                Decode.succeed fqn

                            Err error ->
                                Decode.fail error
                    )
    in
    Decode.map3
        (\displayName entryPoint distribution ->
            Decode.field "data" (decodeDecorationData distribution entryPoint)
                |> Decode.map (DecorationConfigAndData displayName entryPoint distribution)
        )
        (Decode.field "displayName" Decode.string)
        entryPointDecoder
        (Decode.field "iR" decodeVersionedDistribution)
        |> Decode.andThen identity


{-| -}
encodeDecorationData : Distribution -> FQName -> DecorationData -> Encode.Value
encodeDecorationData distribution entryPoint decorationData =
    let
        encodeIrValue =
            decorationData
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
                            distribution
                            (Type.Reference () entryPoint [])
                            |> Result.andThen
                                (\encoderValue ->
                                    irValue |> encoderValue
                                )
                            |> resultToFailure
                        )
                    )
    in
    Encode.object encodeIrValue
