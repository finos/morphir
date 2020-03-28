module Morphir.IR.SDK.Maybe exposing (..)

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
    [ [ "maybe" ] ]


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( [ "maybe" ]
              , CustomTypeSpecification [ [ "a" ] ]
                    [ ( [ "just" ], [ ( [ "value" ], Type.Variable [ "a" ] () ) ] )
                    , ( [ "nothing" ], [] )
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


maybeType : Type extra -> extra -> Type extra
maybeType itemType extra =
    Reference (fromLocalName "maybe") [ itemType ] extra
