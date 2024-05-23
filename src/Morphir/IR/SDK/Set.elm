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


module Morphir.IR.SDK.Set exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Basics exposing (boolType, intType)
import Morphir.IR.SDK.Common exposing (tFun, tVar, toFQName, vSpec)
import Morphir.IR.SDK.List exposing (listType)
import Morphir.IR.SDK.Maybe exposing (maybeType)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Value)


moduleName : ModuleName
moduleName =
    Path.fromString "Set"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Set", OpaqueTypeSpecification [ [ "a" ] ] |> Documented "Type that represents a set." )
            ]
    , values =
        Dict.fromList
            [ vSpec "empty" [] (setType () (tVar "a"))
            , vSpec "singleton" [ ( "a", tVar "comparable" ) ] (setType () (tVar "comparable"))
            , vSpec "insert"
                [ ( "a", tVar "comparable" )
                , ( "set", setType () (tVar "comparable") )
                ]
                (setType () (tVar "comparable"))
            , vSpec "remove"
                [ ( "a", tVar "comparable" )
                , ( "set", setType () (tVar "comparable") )
                ]
                (setType () (tVar "comparable"))
            , vSpec "isEmpty" [ ( "set", setType () (tVar "comparable") ) ] (boolType ())
            , vSpec "member" [ ( "a", tVar "comparable" ), ( "set", setType () (tVar "comparable") ) ] (boolType ())
            , vSpec "size" [ ( "set", setType () (tVar "comparable") ) ] (intType ())
            , vSpec "toList" [ ( "set", setType () (tVar "a") ) ] (listType () (tVar "a"))
            , vSpec "fromList" [ ( "list", listType () (tVar "comparable") ) ] (setType () (tVar "comparable"))
            , vSpec "map"
                [ ( "f", tFun [ tVar "comparable" ] (tVar "comparable2") )
                , ( "set", setType () (tVar "comparable") )
                ]
                (setType () (tVar "comparable2"))
            , vSpec "foldl"
                [ ( "f", tFun [ tVar "a", tVar "b" ] (tVar "b") )
                , ( "z", tVar "b" )
                , ( "set", setType () (tVar "a") )
                ]
                (tVar "b")
            , vSpec "foldr"
                [ ( "f", tFun [ tVar "a", tVar "b" ] (tVar "b") )
                , ( "z", tVar "b" )
                , ( "set", setType () (tVar "a") )
                ]
                (tVar "b")
            , vSpec "filter"
                [ ( "f", tFun [ tVar "comparable" ] (boolType ()) )
                , ( "set", setType () (tVar "comparable") )
                ]
                (setType () (tVar "comparable"))
            , vSpec "partition"
                [ ( "f", tFun [ tVar "comparable" ] (boolType ()) )
                , ( "set", setType () (tVar "comparable") )
                ]
                (Type.Tuple () [ setType () (tVar "comparable"), setType () (tVar "comparable") ])
            , vSpec "union"
                [ ( "set1", setType () (tVar "comparable") )
                , ( "set2", setType () (tVar "comparable") )
                ]
                (setType () (tVar "comparable"))
            , vSpec "intersect"
                [ ( "set1", setType () (tVar "comparable") )
                , ( "set2", setType () (tVar "comparable") )
                ]
                (setType () (tVar "comparable"))
            , vSpec "diff"
                [ ( "set1", setType () (tVar "comparable") )
                , ( "set2", setType () (tVar "comparable") )
                ]
                (setType () (tVar "comparable"))
            ]
    , doc = Just "Contains the Set type, and related functions."
    }


setType : a -> Type a -> Type a
setType attributes itemType =
    Reference attributes (toFQName moduleName "set") [ itemType ]
