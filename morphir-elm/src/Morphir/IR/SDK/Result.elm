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
import Morphir.IR.SDK.Maybe as Maybe exposing (maybeType)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Value.Error exposing (Error(..))
import Morphir.Value.Native as Native


moduleName : ModuleName
moduleName =
    Path.fromString "Result"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Result"
              , CustomTypeSpecification [ Name.fromString "e", Name.fromString "a" ]
                    (Dict.fromList
                        [ ( Name.fromString "Ok", [ ( Name.fromString "value", Type.Variable () (Name.fromString "a") ) ] )
                        , ( Name.fromString "Err", [ ( Name.fromString "error", Type.Variable () (Name.fromString "e") ) ] )
                        ]
                    )
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
    , doc = Just "Contains the Result type (representing the result of an application that can fail), and related functions."
    }


nativeFunctions : List ( String, Native.Function )
nativeFunctions =
    [ ( "andThen"
      , \eval args ->
            case args of
                [ fun, arg1 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                case evaluatedArg1 of
                                    Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) value1 ->
                                        eval (Value.Apply () fun value1)

                                    Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error ->
                                        Ok (err () error)

                                    _ ->
                                        Err (ExpectedResult evaluatedArg1)
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "map"
      , \eval args ->
            case args of
                [ fun, arg1 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                case evaluatedArg1 of
                                    Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) value1 ->
                                        eval (Value.Apply () fun value1) |> Result.map (\value -> ok () value)

                                    Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error ->
                                        Ok (err () error)

                                    _ ->
                                        Err (ExpectedResult evaluatedArg1)
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "map2"
      , \eval args ->
            case args of
                [ fun, arg1, arg2 ] ->
                    Result.map2
                        (\evaluatedArg1 evaluatedArg2 ->
                            case ( evaluatedArg1, evaluatedArg2 ) of
                                ( Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) value1, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) value2 ) ->
                                    eval (Value.Apply () (Value.Apply () fun value1) value2) |> Result.map (\value -> ok () value)

                                ( Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error, _ ) ->
                                    Ok (err () error)

                                ( _, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error ) ->
                                    Ok (err () error)

                                _ ->
                                    Err (UnexpectedArguments [ evaluatedArg1, evaluatedArg2 ])
                        )
                        (eval arg1)
                        (eval arg2)
                        |> Result.andThen identity

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "map3"
      , \eval args ->
            case args of
                [ fun, arg1, arg2, arg3 ] ->
                    Result.map3
                        (\evaluatedArg1 evaluatedArg2 evaluatedArg3 ->
                            case ( evaluatedArg1, evaluatedArg2, evaluatedArg3 ) of
                                ( Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) value1, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) value2, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) value3 ) ->
                                    eval (Value.Apply () (Value.Apply () (Value.Apply () fun value1) value2) value3) |> Result.map (\value -> ok () value)

                                ( Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error, _, _ ) ->
                                    Ok (err () error)

                                ( _, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error, _ ) ->
                                    Ok (err () error)

                                ( _, _, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error ) ->
                                    Ok (err () error)

                                _ ->
                                    Err (UnexpectedArguments [ evaluatedArg1, evaluatedArg2, evaluatedArg3 ])
                        )
                        (eval arg1)
                        (eval arg2)
                        (eval arg3)
                        |> Result.andThen identity

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "map4"
      , \eval args ->
            case args of
                [ fun, arg1, arg2, arg3, arg4 ] ->
                    Result.map4
                        (\evaluatedArg1 evaluatedArg2 evaluatedArg3 evaluatedArg4 ->
                            case [ evaluatedArg1, evaluatedArg2, evaluatedArg3, evaluatedArg4 ] of
                                [ Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) value1, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) value2, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) value3, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) value4 ] ->
                                    eval (Value.Apply () (Value.Apply () (Value.Apply () (Value.Apply () fun value1) value2) value3) value4) |> Result.map (\value -> ok () value)

                                [ Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error, _, _, _ ] ->
                                    Ok (err () error)

                                [ _, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error, _, _ ] ->
                                    Ok (err () error)

                                [ _, _, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error, _ ] ->
                                    Ok (err () error)

                                [ _, _, _, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error ] ->
                                    Ok (err () error)

                                _ ->
                                    Err (UnexpectedArguments [ evaluatedArg1, evaluatedArg2, evaluatedArg3, evaluatedArg4 ])
                        )
                        (eval arg1)
                        (eval arg2)
                        (eval arg3)
                        (eval arg4)
                        |> Result.andThen identity

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "map5"
      , \eval args ->
            case args of
                [ fun, arg1, arg2, arg3, arg4, arg5 ] ->
                    Result.map5
                        (\evaluatedArg1 evaluatedArg2 evaluatedArg3 evaluatedArg4 evaluatedArg5 ->
                            case [ evaluatedArg1, evaluatedArg2, evaluatedArg3, evaluatedArg4, evaluatedArg5 ] of
                                [ Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) value1, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) value2, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) value3, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) value4, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) value5 ] ->
                                    eval (Value.Apply () (Value.Apply () (Value.Apply () (Value.Apply () (Value.Apply () fun value1) value2) value3) value4) value5) |> Result.map (\value -> ok () value)

                                [ Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error, _, _, _, _ ] ->
                                    Ok (err () error)

                                [ _, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error, _, _, _ ] ->
                                    Ok (err () error)

                                [ _, _, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error, _, _ ] ->
                                    Ok (err () error)

                                [ _, _, _, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error, _ ] ->
                                    Ok (err () error)

                                [ _, _, _, _, Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error ] ->
                                    Ok (err () error)

                                _ ->
                                    Err (UnexpectedArguments [ evaluatedArg1, evaluatedArg2, evaluatedArg3, evaluatedArg4 ])
                        )
                        (eval arg1)
                        (eval arg2)
                        (eval arg3)
                        (eval arg4)
                        (eval arg5)
                        |> Result.andThen identity

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "withDefault"
      , \eval args ->
            case args of
                [ arg1, arg2 ] ->
                    eval arg2
                        |> Result.andThen
                            (\evaluatedArg2 ->
                                case evaluatedArg2 of
                                    Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) value ->
                                        Ok value

                                    Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error ->
                                        eval arg1

                                    _ ->
                                        Err (ExpectedResult evaluatedArg2)
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "toMaybe"
      , \eval args ->
            case args of
                [ arg1 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                case evaluatedArg1 of
                                    Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) value ->
                                        Ok (Maybe.just () value)

                                    Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error ->
                                        Ok (Maybe.nothing ())

                                    _ ->
                                        Err (ExpectedResult evaluatedArg1)
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "fromMaybe"
      , \eval args ->
            case args of
                [ arg1, arg2 ] ->
                    eval arg2
                        |> Result.andThen
                            (\evaluatedArg2 ->
                                case evaluatedArg2 of
                                    Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) value ->
                                        Ok (ok () value)

                                    Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ) ->
                                        eval arg1 |> Result.map (\error -> err () error)

                                    _ ->
                                        Err (ExpectedResult evaluatedArg2)
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "mapError"
      , \eval args ->
            case args of
                [ fun, arg1 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                case evaluatedArg1 of
                                    Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "ok" ] )) value ->
                                        Ok (ok () value)

                                    Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "result" ] ], [ "err" ] )) error ->
                                        eval (Value.Apply () fun error) |> Result.map (\errorValue -> err () errorValue)

                                    _ ->
                                        Err (ExpectedResult evaluatedArg1)
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    ]


resultType : a -> Type a -> Type a -> Type a
resultType attributes errorType itemType =
    Reference attributes (toFQName moduleName "result") [ errorType, itemType ]


ok : va -> Value ta va -> Value ta va
ok va value =
    Value.Apply va (Value.Constructor va (toFQName moduleName "Ok")) value


err : va -> Value ta va -> Value ta va
err va error =
    Value.Apply va (Value.Constructor va (toFQName moduleName "Err")) error
