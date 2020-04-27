module Morphir.IR.SDK.Number exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Common exposing (toFQName)
import Morphir.IR.Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Value)


moduleName : ModulePath
moduleName =
    Path.fromString "Number"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.empty
    , values =
        Dict.empty
    }


numberClass : a -> Type a
numberClass attributes =
    Variable attributes [ "number" ]


negate : a -> a -> Value a -> Value a
negate refAttributes valueAttributes arg =
    Value.Apply valueAttributes (Value.Reference refAttributes (toFQName moduleName "negate")) arg


add : a -> Value a
add a =
    Value.Reference a (toFQName moduleName "add")


subtract : a -> Value a
subtract a =
    Value.Reference a (toFQName moduleName "subtract")


multiply : a -> Value a
multiply a =
    Value.Reference a (toFQName moduleName "multiply")


power : a -> Value a
power a =
    Value.Reference a (toFQName moduleName "power")
