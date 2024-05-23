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


module Morphir.IR.SDK.Rule exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Basics exposing (boolType)
import Morphir.IR.SDK.Common exposing (tFun, tVar, toFQName, vSpec)
import Morphir.IR.SDK.List exposing (listType)
import Morphir.IR.SDK.Maybe exposing (maybeType)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Value)


moduleName : ModuleName
moduleName =
    Path.fromString "Rule"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Rule", TypeAliasSpecification [ [ "a" ], [ "b" ] ] (tFun [ tVar "a" ] (maybeType () (tVar "b"))) |> Documented "Type that represents a rule." )
            ]
    , values =
        Dict.fromList
            [ vSpec "chain"
                [ ( "rules", listType () (ruleType () (tVar "a") (tVar "b")) )
                ]
                (ruleType () (tVar "a") (tVar "b"))
            , vSpec "any"
                [ ( "value", tVar "a" )
                ]
                (boolType ())
            , vSpec "is"
                [ ( "ref", tVar "a" )
                , ( "value", tVar "a" )
                ]
                (boolType ())
            , vSpec "anyOf"
                [ ( "ref", listType () (tVar "a") )
                , ( "value", tVar "a" )
                ]
                (boolType ())
            , vSpec "noneOf"
                [ ( "ref", listType () (tVar "a") )
                , ( "value", tVar "a" )
                ]
                (boolType ())
            ]
    , doc = Just "Contains the rule type, and related functions."
    }


ruleType : a -> Type a -> Type a -> Type a
ruleType attributes itemType1 itemType2 =
    Type.Reference attributes (toFQName moduleName "Rule") [ itemType1, itemType2 ]
