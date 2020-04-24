module Morphir.IR.SDK.Comparison exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Common exposing (toFQName)
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


lessThan : a -> Value a
lessThan a =
    Value.Reference a (toFQName moduleName "lessThan")


lessThanOrEqual : a -> Value a
lessThanOrEqual a =
    Value.Reference a (toFQName moduleName "lessThanOrEqual")


greaterThan : a -> Value a
greaterThan a =
    Value.Reference a (toFQName moduleName "greaterThan")


greaterThanOrEqual : a -> Value a
greaterThanOrEqual a =
    Value.Reference a (toFQName moduleName "greaterThanOrEqual")
