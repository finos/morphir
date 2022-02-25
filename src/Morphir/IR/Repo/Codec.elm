module Morphir.IR.Repo.Codec exposing (..)

import Json.Encode as Encode
import Morphir.IR.Repo exposing (Error(..), Errors)


{-| encode a Repo Error
-}
encodeError : Error -> Encode.Value
encodeError error =
    case error of
        ModuleNotFound moduleName ->
            Debug.todo ""

        ModuleHasDependents moduleName set ->
            Debug.todo ""

        ParseError string deadEnds ->
            Debug.todo ""
