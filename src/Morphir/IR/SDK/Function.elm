module Morphir.IR.SDK.Function exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Common exposing (toFQName)
import Morphir.IR.Value as Value exposing (Value)


moduleName : ModulePath
moduleName =
    Path.fromString "Function"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.empty
    , values =
        Dict.empty
    }


composeLeft : a -> Value a
composeLeft a =
    Value.Reference a (toFQName moduleName "composeLeft")


composeRight : a -> Value a
composeRight a =
    Value.Reference a (toFQName moduleName "composeRight")
