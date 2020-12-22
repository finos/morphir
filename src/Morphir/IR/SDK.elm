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

import Dict exposing (Dict)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Basics as Basics
import Morphir.IR.SDK.Char as Char
import Morphir.IR.SDK.Dict as Dict
import Morphir.IR.SDK.List as List
import Morphir.IR.SDK.LocalDate as LocalDate
import Morphir.IR.SDK.Maybe as Maybe
import Morphir.IR.SDK.Month as Month
import Morphir.IR.SDK.Regex as Regex
import Morphir.IR.SDK.Result as Result
import Morphir.IR.SDK.Rule as Rule
import Morphir.IR.SDK.Set as Set
import Morphir.IR.SDK.StatefulApp as StatefulApp
import Morphir.IR.SDK.String as String
import Morphir.IR.SDK.Tuple as Tuple
import Morphir.Value.Native as Native


packageName : PackageName
packageName =
    Path.fromString "Morphir.SDK"


packageSpec : Package.Specification ()
packageSpec =
    { modules =
        Dict.fromList
            [ ( [ [ "basics" ] ], Basics.moduleSpec )
            , ( [ [ "char" ] ], Char.moduleSpec )
            , ( [ [ "dict" ] ], Dict.moduleSpec )
            , ( [ [ "set" ] ], Set.moduleSpec )
            , ( [ [ "string" ] ], String.moduleSpec )
            , ( [ [ "local", "date" ] ], LocalDate.moduleSpec )
            , ( [ [ "maybe" ] ], Maybe.moduleSpec )
            , ( [ [ "month" ] ], Month.moduleSpec )
            , ( [ [ "result" ] ], Result.moduleSpec )
            , ( [ [ "list" ] ], List.moduleSpec )
            , ( [ [ "tuple" ] ], Tuple.moduleSpec )
            , ( [ [ "regex" ] ], Regex.moduleSpec )
            , ( [ [ "stateful", "app" ] ], StatefulApp.moduleSpec )
            , ( [ [ "rule" ] ], Rule.moduleSpec )
            ]
    }


nativeFunctions : Dict ( Path, Path, Name ) Native.Function
nativeFunctions =
    let
        moduleFunctions : String -> List ( String, Native.Function ) -> Dict ( Path, Path, Name ) Native.Function
        moduleFunctions moduleName functionsByName =
            functionsByName
                |> List.map
                    (\( localName, fun ) ->
                        ( ( packageName, Path.fromString moduleName, Name.fromString localName ), fun )
                    )
                |> Dict.fromList
    in
    List.foldl Dict.union
        Dict.empty
        [ moduleFunctions "Basics" Basics.nativeFunctions
        , moduleFunctions "String" String.nativeFunctions
        , moduleFunctions "List" List.nativeFunctions
        ]
