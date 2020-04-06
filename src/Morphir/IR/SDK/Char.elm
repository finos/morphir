module Morphir.IR.SDK.Char exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Common exposing (toFQName)
import Morphir.IR.Type exposing (Specification(..), Type(..))


moduleName : ModulePath
moduleName =
    Path.fromString "Char"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Char", OpaqueTypeSpecification [] )
            ]
    , values =
        Dict.empty
    }


charType : a -> Type a
charType attributes =
    Reference attributes (toFQName moduleName "Char") []
