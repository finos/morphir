module Morphir.IR.SDK.Date exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Common exposing (toFQName)
import Morphir.IR.Type exposing (Specification(..), Type(..))


moduleName : ModulePath
moduleName =
    Path.fromString "LocalDate"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "LocalDate", OpaqueTypeSpecification [] |> Documented "Type that represents a date concept." )
            ]
    , values =
        Dict.empty
    }


dateType : a -> Type a
dateType attributes =
    Reference attributes (toFQName moduleName "LocalDate") []
