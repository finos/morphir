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


module Morphir.IR.SDK.Result exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Common exposing (tFun, tVar, toFQName, vSpec)
import Morphir.IR.SDK.Maybe exposing (maybeType)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))


moduleName : ModuleName
moduleName =
    Path.fromString "Result"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Result"
              , CustomTypeSpecification [ Name.fromString "e", Name.fromString "a" ]
                    [ Type.Constructor (Name.fromString "Ok") [ ( Name.fromString "value", Type.Variable () (Name.fromString "a") ) ]
                    , Type.Constructor (Name.fromString "Err") [ ( Name.fromString "error", Type.Variable () (Name.fromString "e") ) ]
                    ]
                    |> Documented "Type that represents the result of a computation that can either succeed or fail."
              )
            ]
    , values =
        Dict.fromList
            [ vSpec "andThen"
                [ ( "f", tFun [ tVar "a" ] (resultType () (tVar "x") (tVar "b")) )
                , ( "result", resultType () (tVar "x") (tVar "a") )
                ]
                (resultType () (tVar "x") (tVar "b"))
            , vSpec "map"
                [ ( "f", tFun [ tVar "a" ] (tVar "b") )
                , ( "result", resultType () (tVar "x") (tVar "a") )
                ]
                (resultType () (tVar "x") (tVar "b"))
            , vSpec "map2"
                [ ( "f", tFun [ tVar "a", tVar "b" ] (tVar "r") )
                , ( "result1", resultType () (tVar "x") (tVar "a") )
                , ( "result2", resultType () (tVar "x") (tVar "b") )
                ]
                (resultType () (tVar "x") (tVar "r"))
            , vSpec "map3"
                [ ( "f", tFun [ tVar "a", tVar "b", tVar "c" ] (tVar "r") )
                , ( "result1", resultType () (tVar "x") (tVar "a") )
                , ( "result2", resultType () (tVar "x") (tVar "b") )
                , ( "result2", resultType () (tVar "x") (tVar "c") )
                ]
                (resultType () (tVar "x") (tVar "r"))
            , vSpec "map4"
                [ ( "f", tFun [ tVar "a", tVar "b", tVar "c", tVar "d" ] (tVar "r") )
                , ( "result1", resultType () (tVar "x") (tVar "a") )
                , ( "result2", resultType () (tVar "x") (tVar "b") )
                , ( "result2", resultType () (tVar "x") (tVar "c") )
                , ( "result2", resultType () (tVar "x") (tVar "d") )
                ]
                (resultType () (tVar "x") (tVar "r"))
            , vSpec "map5"
                [ ( "f", tFun [ tVar "a", tVar "b", tVar "c", tVar "d", tVar "e" ] (tVar "r") )
                , ( "result1", resultType () (tVar "x") (tVar "a") )
                , ( "result2", resultType () (tVar "x") (tVar "b") )
                , ( "result2", resultType () (tVar "x") (tVar "c") )
                , ( "result2", resultType () (tVar "x") (tVar "d") )
                , ( "result2", resultType () (tVar "x") (tVar "e") )
                ]
                (resultType () (tVar "x") (tVar "r"))
            , vSpec "withDefault"
                [ ( "default", tVar "a" )
                , ( "result", resultType () (tVar "x") (tVar "a") )
                ]
                (tVar "a")
            , vSpec "toMaybe"
                [ ( "result", resultType () (tVar "x") (tVar "a") )
                ]
                (maybeType () (tVar "a"))
            , vSpec "fromMaybe"
                [ ( "error", tVar "x" )
                , ( "maybe", maybeType () (tVar "a") )
                ]
                (resultType () (tVar "x") (tVar "a"))
            , vSpec "mapError"
                [ ( "f", tFun [ tVar "x" ] (tVar "y") )
                , ( "result", resultType () (tVar "x") (tVar "a") )
                ]
                (resultType () (tVar "y") (tVar "a"))
            ]
    }


resultType : a -> Type a -> Type a -> Type a
resultType attributes errorType itemType =
    Reference attributes (toFQName moduleName "result") [ errorType, itemType ]
