module Morphir.IR.SDK.Equality exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Common exposing (toFQName)
import Morphir.IR.Value as Value exposing (Value)


moduleName : ModulePath
moduleName =
    Path.fromString "Equality"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.empty
    , values =
        Dict.empty
    }


equal : a -> Value a
equal a =
    Value.Reference a (toFQName moduleName "equal")


notEqual : a -> Value a
notEqual a =
    Value.Reference a (toFQName moduleName "notEqual")
