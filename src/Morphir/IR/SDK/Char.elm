module Morphir.IR.SDK.Char exposing (..)

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
    [ [ "char" ] ]


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( [ "char" ], OpaqueTypeSpecification [] )
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


charType : extra -> Type extra
charType extra =
    Reference (fromLocalName "char") [] extra
