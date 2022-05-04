module Morphir.IR.Repo.Codec exposing (..)

import Json.Encode as Encode
import Morphir.Dependency.DAG as DAG
import Morphir.Dependency.DAG.Codec exposing (encodeCycleDetected)
import Morphir.IR.FQName.Codec exposing (encodeFQName)
import Morphir.IR.Name.Codec exposing (encodeName)
import Morphir.IR.Path.Codec exposing (encodePath)
import Morphir.IR.Repo exposing (Error(..), Errors)
import Morphir.Type.Infer.Codec exposing (encodeTypeError)


{-| encode a Repo Error
-}
encodeError : Error -> Encode.Value
encodeError error =
    case error of
        ModuleNotFound moduleName ->
            Encode.list identity
                [ Encode.string "ModuleNotFound"
                , encodePath moduleName
                ]

        ModuleHasDependents moduleName dependentModuleNames ->
            Encode.list identity
                [ Encode.string "ModuleHasDependents"
                , encodePath moduleName
                , Encode.set encodePath dependentModuleNames
                ]

        ModuleAlreadyExist moduleName ->
            Encode.list identity
                [ Encode.string "ModuleAlreadyExist"
                , encodePath moduleName
                ]

        TypeAlreadyExist typeName ->
            Encode.list identity
                [ Encode.string "TypeAlreadyExist"
                , encodeFQName typeName
                ]

        DependencyAlreadyExists packageName ->
            Encode.list identity
                [ Encode.string "DependencyAlreadyExists"
                , encodePath packageName
                ]

        ValueAlreadyExist valueName ->
            [ Encode.string "ValueAlreadyExist"
            , Encode.list Encode.string valueName
            ]
                |> Encode.list identity

        TypeCycleDetected cycleDetected ->
            Encode.list identity
                [ Encode.string "TypeCycleDetected"
                , encodeCycleDetected encodeFQName cycleDetected
                ]

        ValueCycleDetected cycleDetected ->
            Encode.list identity
                [ Encode.string "ValueCycleDetected"
                , encodeCycleDetected encodeFQName cycleDetected
                ]

        ModuleCycleDetected cycleDetected ->
            Encode.list identity
                [ Encode.string "ModuleCycleDetected"
                , encodeCycleDetected encodePath cycleDetected
                ]

        TypeCheckError moduleName localName typeError ->
            Encode.list identity
                [ Encode.string "TypeCheckError"
                , encodePath moduleName
                , encodeName localName
                , encodeTypeError typeError
                ]

        CannotInsertType moduleName typeName cause ->
            Encode.list identity
                [ Encode.string "CannotInsertType"
                , encodePath moduleName
                , encodeName typeName
                , encodeError cause
                ]

        ValueNotFound fQName ->
            Encode.list identity
                [ Encode.string "ValueNotFound"
                , encodeFQName fQName
                ]

        IllegalTypeUpdate description ->
            Encode.list identity
                [ Encode.string "IllegalTypeUpdate"
                , Encode.string description
                ]
