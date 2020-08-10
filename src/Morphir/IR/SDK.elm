{-
Copyright 2020 Morgan Stanley

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}


module Morphir.IR.SDK exposing (..)

import Dict
import Morphir.IR.Package as Package exposing (PackagePath)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Bool as Bool
import Morphir.IR.SDK.Char as Char
import Morphir.IR.SDK.Comparable as Comparable
import Morphir.IR.SDK.Float as Float
import Morphir.IR.SDK.Function as Function
import Morphir.IR.SDK.Int as Int
import Morphir.IR.SDK.List as List
import Morphir.IR.SDK.Maybe as Maybe
import Morphir.IR.SDK.Result as Result
import Morphir.IR.SDK.String as String


packageName : PackagePath
packageName =
    Path.fromString "Morphir.SDK"


packageSpec : Package.Specification ()
packageSpec =
    { modules =
        Dict.fromList
            [ ( [ [ "bool" ] ], Bool.moduleSpec )
            , ( [ [ "char" ] ], Char.moduleSpec )
            , ( [ [ "comparable" ] ], Comparable.moduleSpec )
            , ( [ [ "int" ] ], Int.moduleSpec )
            , ( [ [ "float" ] ], Float.moduleSpec )
            , ( [ [ "function" ] ], Function.moduleSpec )
            , ( [ [ "string" ] ], String.moduleSpec )
            , ( [ [ "maybe" ] ], Maybe.moduleSpec )
            , ( [ [ "result" ] ], Result.moduleSpec )
            , ( [ [ "list" ] ], List.moduleSpec )
            ]
    }
