module Morphir.IR.SDK.Bool exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Common exposing (toFQName)
import Morphir.IR.Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Value)


moduleName : ModulePath
moduleName =
    Path.fromString "Bool"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Bool", OpaqueTypeSpecification [] )
            ]
    , values =
        Dict.empty
    }


boolType : a -> Type a
boolType attributes =
    Reference attributes (toFQName moduleName "Bool") []


and : a -> Value a
and a =
    Value.Reference a (toFQName moduleName "and")


or : a -> Value a
or a =
    Value.Reference a (toFQName moduleName "or")
