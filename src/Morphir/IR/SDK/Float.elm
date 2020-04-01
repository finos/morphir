module Morphir.IR.SDK.Float exposing (..)

import Dict
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name
import Morphir.IR.Path exposing (Path)
import Morphir.IR.QName as QName
import Morphir.IR.SDK.Common exposing (packageName)
import Morphir.IR.Type exposing (Specification(..), Type(..))


moduleName : Path
moduleName =
    [ [ "float" ] ]


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( [ "float" ], OpaqueTypeSpecification [] )
            ]
    , values =
        Dict.empty
    }


fromLocalName : String -> FQName
fromLocalName name =
    name
        |> Name.fromString
        |> QName.fromName moduleName
        |> FQName.fromQName packageName


floatType : a -> Type a
floatType attributes =
    Reference attributes (fromLocalName "float") []
