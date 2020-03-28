module Morphir.IR.SDK.Float exposing (..)

import Dict
import Morphir.IR.Advanced.Module as Module
import Morphir.IR.Advanced.Type exposing (Specification(..), Type(..))
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Name as Name
import Morphir.IR.Path exposing (Path)
import Morphir.IR.QName as QName
import Morphir.IR.SDK.Common exposing (packageName)


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


floatType : extra -> Type extra
floatType extra =
    Reference (fromLocalName "float") [] extra
