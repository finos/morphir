module Morphir.IR.SDK.String exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Common exposing (toFQName)
import Morphir.IR.Type exposing (Specification(..), Type(..))


moduleName : ModulePath
moduleName =
    Path.fromString "String"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "String", OpaqueTypeSpecification [] |> Documented "Type that represents a string of characters." )
            ]
    , values =
        Dict.empty
    }


stringType : a -> Type a
stringType attributes =
    Reference attributes (toFQName moduleName "String") []
