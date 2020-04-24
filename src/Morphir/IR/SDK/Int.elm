module Morphir.IR.SDK.Int exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Common exposing (toFQName)
import Morphir.IR.Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Value)


moduleName : ModulePath
moduleName =
    Path.fromString "Int"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Int", OpaqueTypeSpecification [] )
            ]
    , values =
        Dict.empty
    }


intType : a -> Type a
intType attributes =
    Reference attributes (toFQName moduleName "Int") []


divide : a -> Value a
divide a =
    Value.Reference a (toFQName moduleName "divide")
