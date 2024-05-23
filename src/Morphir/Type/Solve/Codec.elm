module Morphir.Type.Solve.Codec exposing (..)

import Json.Encode as Encode
import Morphir.IR.Name.Codec exposing (encodeName)
import Morphir.Type.MetaType.Codec exposing (encodeMetaType)
import Morphir.Type.Solve exposing (UnificationError(..), UnificationErrorType(..))


encodeUnificationError : UnificationError -> Encode.Value
encodeUnificationError unificationError =
    case unificationError of
        UnificationErrors unificationErrors ->
            Encode.list identity
                [ Encode.string "UnificationErrors"
                , Encode.list encodeUnificationError unificationErrors
                ]

        CouldNotUnify unificationErrorType metaType1 metaType2 ->
            Encode.list identity
                [ Encode.string "CouldNotUnify"
                , encodeUnificationErrorType unificationErrorType
                , encodeMetaType metaType1
                , encodeMetaType metaType2
                ]

        CouldNotFindField fieldName ->
            Encode.list identity
                [ Encode.string "CouldNotFindField"
                , encodeName fieldName
                ]


encodeUnificationErrorType : UnificationErrorType -> Encode.Value
encodeUnificationErrorType unificationErrorType =
    case unificationErrorType of
        NoUnificationRule ->
            Encode.string "NoUnificationRule"

        TuplesOfDifferentSize ->
            Encode.string "TuplesOfDifferentSize"

        RefMismatch ->
            Encode.string "RefMismatch"

        FieldMismatch ->
            Encode.string "FieldMismatch"
