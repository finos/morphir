module Morphir.IR.SDK.Comparison exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Common exposing (binaryApply, toFQName)
import Morphir.IR.Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Value)


moduleName : ModulePath
moduleName =
    Path.fromString "Comparison"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.empty
    , values =
        Dict.empty
    }


lessThan : a -> Value a -> Value a -> Value a
lessThan =
    binaryApply moduleName "lessThan"


lessThanOrEqual : a -> Value a -> Value a -> Value a
lessThanOrEqual =
    binaryApply moduleName "lessThanOrEqual"


greaterThan : a -> Value a -> Value a -> Value a
greaterThan =
    binaryApply moduleName "greaterThan"


greaterThanOrEqual : a -> Value a -> Value a -> Value a
greaterThanOrEqual =
    binaryApply moduleName "greaterThanOrEqual"
