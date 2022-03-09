module Morphir.IR.Repo.Codec exposing (..)

import Json.Encode as Encode
import Morphir.IR.Repo exposing (Error(..), Errors)


{-| encode a Repo Error
-}
encodeError : Error -> Encode.Value
encodeError error =
    case error of
        ModuleNotFound moduleName ->
            Encode.list identity
                [ Encode.string "ModuleNotFound"
                , Encode.list (Encode.list Encode.string) moduleName
                ]

        ModuleHasDependents moduleName dependentModuleNames ->
            Encode.list identity
                [ Encode.string "ModuleHasDependents"
                , Encode.list (Encode.list Encode.string) moduleName
                , Encode.set (Encode.list (Encode.list Encode.string)) dependentModuleNames
                ]

        ModuleAlreadyExist moduleName ->
            Encode.list identity
                [ Encode.string "ModuleAlreadyExist"
                , Encode.list (Encode.list Encode.string) moduleName
                ]

        TypeAlreadyExist typeName ->
            [ Encode.string "TypeAlreadyExist"
            , Encode.list Encode.string typeName
            ]
                |> Encode.list identity
