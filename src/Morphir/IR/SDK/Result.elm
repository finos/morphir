module Morphir.IR.SDK.Result exposing (..)

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
    [ [ "result" ] ]


moduleDeclaration : Module.Declaration ()
moduleDeclaration =
    { types =
        Dict.fromList
            [ ( [ "result" ]
              , CustomTypeDeclaration [ [ "e" ], [ "a" ] ]
                    [ ( [ "ok" ], [ ( [ "value" ], Type.Variable [ "a" ] () ) ] )
                    , ( [ "err" ], [ ( [ "error" ], Type.Variable [ "e" ] () ) ] )
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


resultType : Type extra -> extra -> Type extra
resultType itemType extra =
    Reference (fromLocalName "result") [ itemType ] extra
