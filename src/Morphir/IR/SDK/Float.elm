module Morphir.IR.SDK.Float exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Common exposing (toFQName)
import Morphir.IR.Type exposing (Specification(..), Type(..))


moduleName : ModulePath
moduleName =
    Path.fromString "Float"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Float", OpaqueTypeSpecification [] )
            ]
    , values =
        Dict.empty
    }


floatType : a -> Type a
floatType attributes =
    Reference attributes (toFQName moduleName "Float") []
