module Morphir.IR.SDK exposing (..)

import Dict
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Bool as Bool
import Morphir.IR.SDK.Char as Char
import Morphir.IR.SDK.Float as Float
import Morphir.IR.SDK.Int as Int
import Morphir.IR.SDK.List as List
import Morphir.IR.SDK.Maybe as Maybe
import Morphir.IR.SDK.Result as Result
import Morphir.IR.SDK.String as String


packageName : Path
packageName =
    Path.fromString "Morphir.SDK"


packageSpec : Package.Specification ()
packageSpec =
    { modules =
        Dict.fromList
            [ ( [ [ "bool" ] ], Bool.moduleSpec )
            , ( [ [ "char" ] ], Char.moduleSpec )
            , ( [ [ "int" ] ], Int.moduleSpec )
            , ( [ [ "float" ] ], Float.moduleSpec )
            , ( [ [ "string" ] ], String.moduleSpec )
            , ( [ [ "maybe" ] ], Maybe.moduleSpec )
            , ( [ [ "result" ] ], Result.moduleSpec )
            , ( [ [ "list" ] ], List.moduleSpec )
            ]
    }
