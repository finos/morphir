module Morphir.IR.SDK exposing (..)

import Dict
import Morphir.IR.Advanced.Package as Package
import Morphir.IR.SDK.Bool as Bool
import Morphir.IR.SDK.Char as Char
import Morphir.IR.SDK.Float as Float
import Morphir.IR.SDK.Int as Int
import Morphir.IR.SDK.List as List
import Morphir.IR.SDK.Maybe as Maybe
import Morphir.IR.SDK.Result as Result
import Morphir.IR.SDK.String as String


packageDeclaration : Package.Declaration ()
packageDeclaration =
    { modules =
        Dict.fromList
            [ ( [ [ "bool" ] ], Bool.moduleDeclaration )
            , ( [ [ "char" ] ], Char.moduleDeclaration )
            , ( [ [ "int" ] ], Int.moduleDeclaration )
            , ( [ [ "float" ] ], Float.moduleDeclaration )
            , ( [ [ "string" ] ], String.moduleDeclaration )
            , ( [ [ "maybe" ] ], Maybe.moduleDeclaration )
            , ( [ [ "result" ] ], Result.moduleDeclaration )
            , ( [ [ "list" ] ], List.moduleDeclaration )
            ]
    }
