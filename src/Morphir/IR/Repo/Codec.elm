module Morphir.IR.Repo.Codec exposing (..)

import Json.Encode as Encode
import Morphir.Elm.ModuleName as ModuleName
import Morphir.IR.Repo exposing (Error(..), Errors)


{-| encode a Repo Error
-}
encodeError : Error -> Encode.Value
encodeError error =
    case error of
        ModuleNotFound moduleName ->
            moduleName
                |> ModuleName.fromIRModuleName
                |> ModuleName.toString
                |> (\moduleNameAsString ->
                        String.concat [ "Module not found: ", moduleNameAsString ]
                   )
                |> Encode.string

        ModuleHasDependents moduleName dependentModuleNames ->
            Encode.list identity
                [ Encode.string
                    (String.concat
                        [ "The following modules depend on "
                        , moduleName
                            |> ModuleName.fromIRModuleName
                            |> ModuleName.toString
                        ]
                    )
                , Encode.set
                    (ModuleName.fromIRModuleName
                        >> ModuleName.toString
                        >> Encode.string
                    )
                    dependentModuleNames
                ]

        ModuleAlreadyExist moduleName ->
            String.concat
                [ moduleName
                    |> ModuleName.fromIRModuleName
                    |> ModuleName.toString
                , " Already exists"
                ]
                |> Encode.string

        TypeAlreadyExist name ->
            Debug.todo ""
