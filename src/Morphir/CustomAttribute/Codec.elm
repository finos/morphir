module Morphir.CustomAttribute.Codec exposing (..)

import Dict exposing (Dict)
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.CustomAttribute.CustomAttribute exposing (CustomAttribute, CustomAttributeConfig)
import Morphir.IR.FQName as FQName


encodeCustomAttributeConfig : CustomAttributeConfig -> Encode.Value
encodeCustomAttributeConfig customAttributeConfig =
    Encode.object
        [ ( "filePath", Encode.string customAttributeConfig.filePath )
        ]


decodeCustomAttributeConfig : Decode.Decoder CustomAttributeConfig
decodeCustomAttributeConfig =
    Decode.map CustomAttributeConfig
        (Decode.field "filePath" Decode.string)


decodeAttributes : Decode.Decoder CustomAttribute
decodeAttributes =
    let
        flattenNestedStructure : Dict String (Dict String Decode.Value) -> CustomAttribute
        flattenNestedStructure nestedDict =
            Dict.foldl
                (\attrName fQNameDict flat ->
                    Dict.foldl
                        (\fQName value innerFlat ->
                            case Dict.get (FQName.fromString "." fQName) innerFlat of
                                Just dict ->
                                    Dict.insert (FQName.fromString "." fQName) (Dict.insert attrName value dict) innerFlat

                                Nothing ->
                                    Dict.insert (FQName.fromString "." fQName) (Dict.insert attrName value Dict.empty) innerFlat
                        )
                        flat
                        fQNameDict
                )
                Dict.empty
                nestedDict
    in
    Decode.map flattenNestedStructure (Decode.dict (Decode.dict Decode.value))
