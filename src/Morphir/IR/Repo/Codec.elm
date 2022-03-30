module Morphir.IR.Repo.Codec exposing (..)

import Json.Encode as Encode
import Morphir.IR.FQName.Codec exposing (encodeFQName)
import Morphir.IR.Path.Codec exposing (encodePath)
import Morphir.IR.Repo exposing (Error(..), Errors)


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

        TypeCycleDetected typeName ->
            [ Encode.string "TypeCycleDetected"
            , Encode.list Encode.string typeName
            ]
                |> Encode.list identity

        ValueCycleDetected valueName ->
            [ Encode.string "ValueCycleDetected"
            , Encode.list Encode.string valueName
            ]
                |> Encode.list identity
