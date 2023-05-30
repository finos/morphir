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


module Morphir.IR.SDK.Tuple exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Common exposing (tFun, tVar, vSpec)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value
import Morphir.Value.Error exposing (Error(..))
import Morphir.Value.Native as Native exposing (decodeRaw, decodeTuple2, encodeRaw, encodeTuple2, eval1, eval2)


moduleName : ModuleName
moduleName =
    Path.fromString "Tuple"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.empty
    , values =
        Dict.fromList
            [ vSpec "pair"
                [ ( "a", tVar "a" )
                , ( "b", tVar "b" )
                ]
                (Type.Tuple () [ tVar "a", tVar "b" ])
            , vSpec "first"
                [ ( "tuple", Type.Tuple () [ tVar "a", tVar "b" ] )
                ]
                (tVar "a")
            , vSpec "second"
                [ ( "tuple", Type.Tuple () [ tVar "a", tVar "b" ] )
                ]
                (tVar "b")
            , vSpec "mapFirst"
                [ ( "f", tFun [ tVar "a" ] (tVar "x") )
                , ( "tuple", Type.Tuple () [ tVar "a", tVar "b" ] )
                ]
                (Type.Tuple () [ tVar "x", tVar "b" ])
            , vSpec "mapSecond"
                [ ( "f", tFun [ tVar "b" ] (tVar "y") )
                , ( "tuple", Type.Tuple () [ tVar "a", tVar "b" ] )
                ]
                (Type.Tuple () [ tVar "a", tVar "y" ])
            , vSpec "mapBoth"
                [ ( "f", tFun [ tVar "a" ] (tVar "x") )
                , ( "g", tFun [ tVar "b" ] (tVar "y") )
                , ( "tuple", Type.Tuple () [ tVar "a", tVar "b" ] )
                ]
                (Type.Tuple () [ tVar "x", tVar "y" ])
            ]
    , doc = Just "Functions related to Tuples"
    }


nativeFunctions : List ( String, Native.Function )
nativeFunctions =
    [ ( "pair", eval2 Tuple.pair decodeRaw decodeRaw (encodeTuple2 ( encodeRaw, encodeRaw )) )
    , ( "first", eval1 Tuple.first (decodeTuple2 ( decodeRaw, decodeRaw )) encodeRaw )
    , ( "second", eval1 Tuple.second (decodeTuple2 ( decodeRaw, decodeRaw )) encodeRaw )
    , ( "mapFirst"
      , \eval args ->
            case args of
                [ fun, arg1 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                case evaluatedArg1 of
                                    Value.Tuple () [ val1, val2 ] ->
                                        eval (Value.Apply () fun val1)
                                            |> Result.andThen
                                                (\evaluatedValue1 ->
                                                    Value.Tuple () [ evaluatedValue1, val2 ] |> Ok
                                                )

                                    _ ->
                                        Err (ExpectedTuple evaluatedArg1)
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "mapSecond"
      , \eval args ->
            case args of
                [ fun, arg1 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                case evaluatedArg1 of
                                    Value.Tuple () [ val1, val2 ] ->
                                        eval (Value.Apply () fun val2)
                                            |> Result.andThen
                                                (\evaluatedValue2 ->
                                                    Value.Tuple () [ val1, evaluatedValue2 ] |> Ok
                                                )

                                    _ ->
                                        Err (ExpectedTuple evaluatedArg1)
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "mapBoth"
      , \eval args ->
            case args of
                [ fun1, fun2, arg1 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                case evaluatedArg1 of
                                    Value.Tuple () [ val1, val2 ] ->
                                        Result.map2
                                            (\evaluatedValue1 evaluatedValue2 ->
                                                Value.Tuple () [ evaluatedValue1, evaluatedValue2 ] |> Ok
                                            )
                                            (eval (Value.Apply () fun1 val1))
                                            (eval (Value.Apply () fun2 val2))
                                            |> Result.andThen identity

                                    _ ->
                                        Err (ExpectedTuple evaluatedArg1)
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    ]
