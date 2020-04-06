module Morphir.IR.SDK.Bool exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Common exposing (binaryApply, toFQName)
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


and : a -> Value a -> Value a -> Value a
and =
    binaryApply moduleName "and"


or : a -> Value a -> Value a -> Value a
or =
    binaryApply moduleName "or"
