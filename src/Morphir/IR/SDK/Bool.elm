module Morphir.IR.SDK.Bool exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Common exposing (toFQName)
import Morphir.IR.Type exposing (Specification(..), Type(..))


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
