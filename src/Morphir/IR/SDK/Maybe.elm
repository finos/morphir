module Morphir.IR.SDK.Maybe exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Common exposing (toFQName)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))


moduleName : ModulePath
moduleName =
    Path.fromString "Maybe"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Maybe"
              , CustomTypeSpecification [ Name.fromString "a" ]
                    [ Type.Constructor (Name.fromString "Just") [ ( [ "value" ], Type.Variable () (Name.fromString "a") ) ]
                    , Type.Constructor (Name.fromString "Nothing") []
                    ]
              )
            ]
    , values =
        Dict.empty
    }


maybeType : a -> Type a -> Type a
maybeType attributes itemType =
    Reference attributes (toFQName moduleName "Maybe") [ itemType ]
