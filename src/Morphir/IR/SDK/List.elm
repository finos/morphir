module Morphir.IR.SDK.List exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Common exposing (binaryApply, toFQName)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value exposing (Value)


moduleName : ModulePath
moduleName =
    Path.fromString "List"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "List", OpaqueTypeSpecification [ [ "a" ] ] )
            ]
    , values =
        Dict.empty
    }


listType : a -> Type a -> Type a
listType attributes itemType =
    Type.Reference attributes (toFQName moduleName "List") [ itemType ]


construct : a -> Value a -> Value a -> Value a
construct =
    binaryApply moduleName "construct"
