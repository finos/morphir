module Morphir.IR.SDK.List exposing (..)

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
    [ [ "list" ] ]


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( [ "list" ], OpaqueTypeSpecification [ [ "a" ] ] )
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


listType : a -> Type a -> Type a
listType attributes itemType =
    Reference attributes (fromLocalName "list") [ itemType ]
