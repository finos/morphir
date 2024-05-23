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


module Morphir.IR.SDK.ResultList exposing (moduleName, moduleSpec, nativeFunctions)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Basics exposing (boolType)
import Morphir.IR.SDK.Common exposing (tFun, tVar, toFQName, vSpec)
import Morphir.IR.SDK.List exposing (listType)
import Morphir.IR.SDK.Result exposing (resultType)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.Value.Native as Native


moduleName : ModuleName
moduleName =
    Path.fromString "ResultList"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "ResultList"
              , TypeAliasSpecification [ [ "e" ], [ "a" ] ]
                    (listType () (resultType () (tVar "e") (tVar "a")))
                    |> Documented "Type that represents a list of results."
              )
            ]
    , values =
        Dict.fromList
            [ vSpec "fromList"
                [ ( "list", listType () (tVar "a") )
                ]
                (resultListType () (tVar "e") (tVar "a"))
            , vSpec "filter"
                [ ( "f", tFun [ tVar "a" ] (boolType ()) )
                , ( "list", resultListType () (tVar "e") (tVar "a") )
                ]
                (resultListType () (tVar "e") (tVar "a"))
            , vSpec "filterOrFail"
                [ ( "f", tFun [ tVar "a" ] (resultType () (tVar "e") (boolType ())) )
                , ( "list", resultListType () (tVar "e") (tVar "a") )
                ]
                (resultListType () (tVar "e") (tVar "a"))
            , vSpec "map"
                [ ( "f", tFun [ tVar "a" ] (tVar "b") )
                , ( "list", resultListType () (tVar "e") (tVar "a") )
                ]
                (resultListType () (tVar "e") (tVar "b"))
            , vSpec "mapOrFail"
                [ ( "f", tFun [ tVar "a" ] (resultType () (tVar "e") (tVar "b")) )
                , ( "list", resultListType () (tVar "e") (tVar "a") )
                ]
                (resultListType () (tVar "e") (tVar "b"))
            , vSpec "errors"
                [ ( "list", resultListType () (tVar "e") (tVar "a") )
                ]
                (listType () (tVar "e"))
            , vSpec "successes"
                [ ( "list", resultListType () (tVar "e") (tVar "a") )
                ]
                (listType () (tVar "a"))
            , vSpec "partition"
                [ ( "list", resultListType () (tVar "e") (tVar "a") )
                ]
                (Type.Tuple () [ listType () (tVar "e"), listType () (tVar "a") ])
            , vSpec "keepAllErrors"
                [ ( "list", resultListType () (tVar "e") (tVar "a") )
                ]
                (resultType () (listType () (tVar "e")) (listType () (tVar "a")))
            , vSpec "keepFirstError"
                [ ( "list", resultListType () (tVar "e") (tVar "a") )
                ]
                (resultType () (tVar "e") (listType () (tVar "a")))
            ]
    , doc = Just "Contains the ResultList type, and related functions."
    }


resultListType : a -> Type a -> Type a -> Type a
resultListType attributes errorType itemType =
    Type.Reference attributes (toFQName moduleName "ResultList") [ errorType, itemType ]


nativeFunctions : List ( String, Native.Function )
nativeFunctions =
    []
