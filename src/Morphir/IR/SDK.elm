module Morphir.IR.SDK exposing (..)

import Dict
import Morphir.IR.Advanced.Package as Package
import Morphir.IR.SDK.Int as Int


packageDeclaration : Package.Declaration ()
packageDeclaration =
    { modules =
        Dict.fromList
            [ ( [ [ "int" ] ], Int.moduleDeclaration )
            ]
    }
