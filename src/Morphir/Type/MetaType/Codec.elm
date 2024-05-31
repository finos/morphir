module Morphir.Type.MetaType.Codec exposing (..)

import Dict
import Json.Encode as Encode
import Morphir.IR.FQName.Codec exposing (encodeFQName)
import Morphir.IR.Name.Codec exposing (encodeName)
import Morphir.Type.MetaType exposing (MetaType(..), Variable)


encodeMetaType : MetaType -> Encode.Value
encodeMetaType metaType =
    case metaType of
        MetaVar variable ->
            Encode.list identity
                [ Encode.string "meta_var"
                , encodeVariable variable
                ]

        MetaRef _ fQName args maybeAliasedType ->
            Encode.list identity
                [ Encode.string "meta_ref"
                , encodeFQName fQName
                , Encode.list encodeMetaType args
                , case maybeAliasedType of
                    Just aliasedType ->
                        encodeMetaType aliasedType

                    Nothing ->
                        Encode.null
                ]

        MetaTuple _ metaTypes ->
            Encode.list identity
                [ Encode.string "meta_tuple"
                , Encode.list encodeMetaType metaTypes
                ]

        MetaRecord _ recordVar isOpen dict ->
            Encode.list identity
                [ Encode.string "meta_record"
                , encodeVariable recordVar
                , Encode.bool isOpen
                , dict
                    |> Dict.toList
                    |> Encode.list
                        (\( fieldName, fieldType ) ->
                            Encode.list identity
                                [ encodeName fieldName
                                , encodeMetaType fieldType
                                ]
                        )
                ]

        MetaFun _ metaType1 metaType2 ->
            Encode.list identity
                [ Encode.string "meta_fun"
                , encodeMetaType metaType1
                , encodeMetaType metaType2
                ]

        MetaUnit ->
            Encode.list identity
                [ Encode.string "meta_unit"
                ]


encodeVariable : Variable -> Encode.Value
encodeVariable i =
    Encode.int i
