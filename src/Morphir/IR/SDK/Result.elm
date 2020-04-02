module Morphir.IR.SDK.Result exposing (..)

import Dict
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name
import Morphir.IR.Path exposing (Path)
import Morphir.IR.QName as QName
import Morphir.IR.SDK.Common exposing (packageName)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))


moduleName : Path
moduleName =
    [ [ "result" ] ]


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( [ "result" ]
              , CustomTypeSpecification [ [ "e" ], [ "a" ] ]
                    [ Type.Constructor [ "ok" ] [ ( [ "value" ], Type.Variable () [ "a" ] ) ]
                    , Type.Constructor [ "err" ] [ ( [ "error" ], Type.Variable () [ "e" ] ) ]
                    ]
              )
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


resultType : a -> Type a -> Type a
resultType attributes itemType =
    Reference attributes (fromLocalName "result") [ itemType ]
