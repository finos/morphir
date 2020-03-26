module Morphir.IR.SDK.Maybe exposing (..)

import Dict
import Morphir.IR.Advanced.Module as Module
import Morphir.IR.Advanced.Type as Type exposing (Declaration(..), Type(..))
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Name as Name
import Morphir.IR.Path exposing (Path)
import Morphir.IR.QName as QName
import Morphir.IR.SDK.Common exposing (packageName)


moduleName : Path
moduleName =
    [ [ "maybe" ] ]


moduleDeclaration : Module.Declaration ()
moduleDeclaration =
    { types =
        Dict.fromList
            [ ( [ "maybe" ]
              , CustomTypeDeclaration [ [ "a" ] ]
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
