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


module Morphir.IR.SDK.Aggregate exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Basics exposing (boolType, floatType, intType, orderType)
import Morphir.IR.SDK.Common exposing (tFun, tVar, toFQName, vSpec)
import Morphir.IR.SDK.Dict exposing (dictType)
import Morphir.IR.SDK.Key exposing (key0Type)
import Morphir.IR.SDK.List exposing (listType)
import Morphir.IR.SDK.Maybe exposing (maybeType)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Value)
import Morphir.SDK.ResultList as ListOfResults
import Morphir.Value.Error exposing (Error(..))
import Morphir.Value.Native as Native


moduleName : ModuleName
moduleName =
    Path.fromString "Aggregate"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Aggregation", OpaqueTypeSpecification [ [ "a" ], [ "key" ] ] |> Documented "" )
            , ( Name.fromString "Aggregator", TypeAliasSpecification [ [ "a" ], [ "key" ] ] (tFun [ aggregationType () (tVar "a") (tVar "key") ] (floatType ())) |> Documented "" )
            ]
    , values =
        Dict.fromList
            [ vSpec "count"
                []
                (aggregationType () (tVar "a") (key0Type ()))
            , vSpec "sumOf"
                [ ( "getValue", tFun [ tVar "a" ] (floatType ()) )
                ]
                (aggregationType () (tVar "a") (key0Type ()))
            , vSpec "averageOf"
                [ ( "getValue", tFun [ tVar "a" ] (floatType ()) )
                ]
                (aggregationType () (tVar "a") (key0Type ()))
            , vSpec "minimumOf"
                [ ( "getValue", tFun [ tVar "a" ] (floatType ()) )
                ]
                (aggregationType () (tVar "a") (key0Type ()))
            , vSpec "maximumOf"
                [ ( "getValue", tFun [ tVar "a" ] (floatType ()) )
                ]
                (aggregationType () (tVar "a") (key0Type ()))
            , vSpec "weightedAverageOf"
                [ ( "getWeight", tFun [ tVar "a" ] (floatType ()) )
                , ( "getValue", tFun [ tVar "a" ] (floatType ()) )
                ]
                (aggregationType () (tVar "a") (key0Type ()))
            , vSpec "byKey"
                [ ( "key", tFun [ tVar "a" ] (tVar "key") )
                , ( "agg", aggregationType () (tVar "a") (key0Type ()) )
                ]
                (aggregationType () (tVar "a") (tVar "key"))
            , vSpec "withFilter"
                [ ( "filter", tFun [ tVar "a" ] (boolType ()) )
                , ( "agg", aggregationType () (tVar "a") (tVar "key") )
                ]
                (aggregationType () (tVar "a") (tVar "key"))
            , vSpec "aggregateMap"
                [ ( "agg1", aggregationType () (tVar "a") (tVar "key1") )
                , ( "f", tFun [ floatType (), tVar "a" ] (tVar "b") )
                , ( "list", listType () (tVar "a") )
                ]
                (listType () (tVar "b"))
            , vSpec "aggregateMap2"
                [ ( "agg1", aggregationType () (tVar "a") (tVar "key1") )
                , ( "agg2", aggregationType () (tVar "a") (tVar "key2") )
                , ( "f", tFun [ floatType (), floatType (), tVar "a" ] (tVar "b") )
                , ( "list", listType () (tVar "a") )
                ]
                (listType () (tVar "b"))
            , vSpec "aggregateMap3"
                [ ( "agg1", aggregationType () (tVar "a") (tVar "key1") )
                , ( "agg2", aggregationType () (tVar "a") (tVar "key2") )
                , ( "agg3", aggregationType () (tVar "a") (tVar "key3") )
                , ( "f", tFun [ floatType (), floatType (), floatType (), tVar "a" ] (tVar "b") )
                , ( "list", listType () (tVar "a") )
                ]
                (listType () (tVar "b"))
            , vSpec "aggregateMap4"
                [ ( "agg1", aggregationType () (tVar "a") (tVar "key1") )
                , ( "agg2", aggregationType () (tVar "a") (tVar "key2") )
                , ( "agg3", aggregationType () (tVar "a") (tVar "key3") )
                , ( "agg4", aggregationType () (tVar "a") (tVar "key4") )
                , ( "f", tFun [ floatType (), floatType (), floatType (), floatType (), tVar "a" ] (tVar "b") )
                , ( "list", listType () (tVar "a") )
                ]
                (listType () (tVar "b"))
            , vSpec "groupBy"
                [ ( "getKey", tFun [ tVar "a" ] (tVar "key") )
                , ( "list", listType () (tVar "a") )
                ]
                (dictType () (tVar "key") (listType () (tVar "a")))
            , vSpec "aggregate"
                [ ( "f", tFun [ tVar "key", aggregatorType () (tVar "a") (key0Type ()) ] (tVar "b") )
                , ( "dict", dictType () (tVar "key") (listType () (tVar "a")) )
                ]
                (listType () (tVar "b"))
            ]
    , doc = Just "Aggregation type and associated functions."
    }


aggregationType : a -> Type a -> Type a -> Type a
aggregationType attributes aType keyType =
    Type.Reference attributes (toFQName moduleName "Aggregation") [ aType, keyType ]


aggregatorType : a -> Type a -> Type a -> Type a
aggregatorType attributes aType keyType =
    Type.Reference attributes (toFQName moduleName "Aggregator") [ aType, keyType ]


nativeFunctions : List ( String, Native.Function )
nativeFunctions =
    []
