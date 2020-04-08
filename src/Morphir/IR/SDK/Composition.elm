module Morphir.IR.SDK.Composition exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Common exposing (binaryApply, toFQName)
import Morphir.IR.Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Value)


moduleName : ModulePath
moduleName =
    Path.fromString "Composition"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.empty
    , values =
        Dict.empty
    }


composeLeft : a -> Value a -> Value a -> Value a
composeLeft =
    binaryApply moduleName "composeLeft"


composeRight : a -> Value a -> Value a -> Value a
composeRight =
    binaryApply moduleName "composeRight"
