module Morphir.IR.SDK.Result exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Common exposing (toFQName)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))


moduleName : ModulePath
moduleName =
    Path.fromString "Result"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Result"
              , CustomTypeSpecification [ Name.fromString "e", Name.fromString "a" ]
                    [ Type.Constructor (Name.fromString "Ok") [ ( Name.fromString "value", Type.Variable () (Name.fromString "a") ) ]
                    , Type.Constructor (Name.fromString "Err") [ ( Name.fromString "error", Type.Variable () (Name.fromString "e") ) ]
                    ]
              )
            ]
    , values =
        Dict.empty
    }


resultType : a -> Type a -> Type a
resultType attributes itemType =
    Reference attributes (toFQName moduleName "result") [ itemType ]
