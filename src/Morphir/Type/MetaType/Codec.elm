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

        MetaRef fQName ->
            Encode.list identity
                [ Encode.string "meta_ref"
                , encodeFQName fQName
                ]

        MetaTuple metaTypes ->
            Encode.list identity
                [ Encode.string "meta_tuple"
                , Encode.list encodeMetaType metaTypes
                ]

        MetaRecord maybeVar dict ->
            Encode.list identity
                [ Encode.string "meta_record"
                , case maybeVar of
                    Just var ->
                        encodeVariable var

                    Nothing ->
                        Encode.null
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

        MetaApply metaType1 metaType2 ->
            Encode.list identity
                [ Encode.string "meta_apply"
                , encodeMetaType metaType1
                , encodeMetaType metaType2
                ]

        MetaFun metaType1 metaType2 ->
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
encodeVariable ( i, s ) =
    Encode.list Encode.int [ i, s ]
