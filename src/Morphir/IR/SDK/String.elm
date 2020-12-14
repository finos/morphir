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


module Morphir.IR.SDK.String exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Basics exposing (boolType, floatType, intType)
import Morphir.IR.SDK.Char exposing (charType)
import Morphir.IR.SDK.Common exposing (tFun, tVar, toFQName, vSpec)
import Morphir.IR.SDK.List exposing (listType)
import Morphir.IR.SDK.Maybe exposing (maybeType)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value
import Morphir.ListOfResults as ListOfResults
import Morphir.Value.Error exposing (Error(..))
import Morphir.Value.Native as Native


moduleName : ModuleName
moduleName =
    Path.fromString "String"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "String", OpaqueTypeSpecification [] |> Documented "Type that represents a string of characters." )
            ]
    , values =
        Dict.fromList
            [ vSpec "isEmpty" [ ( "s", stringType () ) ] (boolType ())
            , vSpec "length" [ ( "s", stringType () ) ] (intType ())
            , vSpec "reverse" [ ( "s", stringType () ) ] (stringType ())
            , vSpec "repeat" [ ( "n", intType () ), ( "s", stringType () ) ] (stringType ())
            , vSpec "replace" [ ( "match", stringType () ), ( "replacement", stringType () ), ( "s", stringType () ) ] (stringType ())
            , vSpec "append" [ ( "s1", stringType () ), ( "s2", stringType () ) ] (stringType ())
            , vSpec "concat" [ ( "list", listType () (stringType ()) ) ] (stringType ())
            , vSpec "split" [ ( "sep", stringType () ), ( "s", stringType () ) ] (listType () (stringType ()))
            , vSpec "join" [ ( "sep", stringType () ), ( "list", listType () (stringType ()) ) ] (stringType ())
            , vSpec "words" [ ( "s", stringType () ) ] (listType () (stringType ()))
            , vSpec "lines" [ ( "s", stringType () ) ] (listType () (stringType ()))
            , vSpec "slice" [ ( "start", intType () ), ( "end", intType () ), ( "s", stringType () ) ] (stringType ())
            , vSpec "left" [ ( "n", intType () ), ( "s", stringType () ) ] (stringType ())
            , vSpec "right" [ ( "n", intType () ), ( "s", stringType () ) ] (stringType ())
            , vSpec "dropLeft" [ ( "n", intType () ), ( "s", stringType () ) ] (stringType ())
            , vSpec "dropRight" [ ( "n", intType () ), ( "s", stringType () ) ] (stringType ())
            , vSpec "contains" [ ( "ref", stringType () ), ( "s", stringType () ) ] (boolType ())
            , vSpec "startsWith" [ ( "ref", stringType () ), ( "s", stringType () ) ] (boolType ())
            , vSpec "endsWith" [ ( "ref", stringType () ), ( "s", stringType () ) ] (boolType ())
            , vSpec "indexes" [ ( "ref", stringType () ), ( "s", stringType () ) ] (listType () (intType ()))
            , vSpec "indices" [ ( "ref", stringType () ), ( "s", stringType () ) ] (listType () (intType ()))
            , vSpec "toInt" [ ( "s", stringType () ) ] (maybeType () (intType ()))
            , vSpec "fromInt" [ ( "a", intType () ) ] (stringType ())
            , vSpec "toFloat" [ ( "s", stringType () ) ] (maybeType () (floatType ()))
            , vSpec "fromFloat" [ ( "a", floatType () ) ] (stringType ())
            , vSpec "fromChar" [ ( "ch", charType () ) ] (stringType ())
            , vSpec "cons" [ ( "ch", charType () ), ( "s", stringType () ) ] (stringType ())
            , vSpec "uncons" [ ( "s", stringType () ) ] (maybeType () (Type.Tuple () [ charType (), stringType () ]))
            , vSpec "toList" [ ( "s", stringType () ) ] (listType () (charType ()))
            , vSpec "fromList" [ ( "a", listType () (charType ()) ) ] (stringType ())
            , vSpec "toUpper" [ ( "s", stringType () ) ] (stringType ())
            , vSpec "toLower" [ ( "s", stringType () ) ] (stringType ())
            , vSpec "pad" [ ( "n", intType () ), ( "s", stringType () ) ] (stringType ())
            , vSpec "padLeft" [ ( "n", intType () ), ( "s", stringType () ) ] (stringType ())
            , vSpec "padRight" [ ( "n", intType () ), ( "s", stringType () ) ] (stringType ())
            , vSpec "trim" [ ( "s", stringType () ) ] (stringType ())
            , vSpec "trimLeft" [ ( "s", stringType () ) ] (stringType ())
            , vSpec "trimRight" [ ( "s", stringType () ) ] (stringType ())
            , vSpec "map" [ ( "f", tFun [ charType () ] (charType ()) ), ( "s", stringType () ) ] (stringType ())
            , vSpec "filter" [ ( "f", tFun [ charType () ] (boolType ()) ), ( "s", stringType () ) ] (stringType ())
            , vSpec "foldl" [ ( "f", tFun [ charType (), tVar "b" ] (tVar "b") ), ( "z", tVar "b" ), ( "s", stringType () ) ] (tVar "b")
            , vSpec "foldr" [ ( "f", tFun [ charType (), tVar "b" ] (tVar "b") ), ( "z", tVar "b" ), ( "s", stringType () ) ] (tVar "b")
            , vSpec "any" [ ( "f", tFun [ charType () ] (boolType ()) ), ( "s", stringType () ) ] (boolType ())
            , vSpec "all" [ ( "f", tFun [ charType () ] (boolType ()) ), ( "s", stringType () ) ] (boolType ())
            ]
    }


stringType : a -> Type a
stringType attributes =
    Reference attributes (toFQName moduleName "String") []


nativeFunctions : List ( String, Native.Function )
nativeFunctions =
    [ ( "concat"
      , Native.unaryStrict
            (\eval arg ->
                case arg of
                    Value.List _ value ->
                        value
                            |> List.map
                                (\listItem ->
                                    eval listItem
                                        |> Result.andThen
                                            (\evaluatedListItem ->
                                                case evaluatedListItem of
                                                    Value.Literal _ (StringLiteral argument) ->
                                                        Ok argument

                                                    _ ->
                                                        Err (UnexpectedArguments [ arg ])
                                            )
                                )
                            |> ListOfResults.liftFirstError
                            |> Result.map (String.concat >> StringLiteral >> Value.Literal ())

                    _ ->
                        Err (UnexpectedArguments [ arg ])
            )
      )
    ]
