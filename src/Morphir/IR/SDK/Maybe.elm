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


module Morphir.IR.SDK.Maybe exposing (just, maybeType, moduleName, moduleSpec, nativeFunctions, nothing)

import Dict
import Maybe
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Basics exposing (boolType)
import Morphir.IR.SDK.Common exposing (tFun, tVar, toFQName, vSpec)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Pattern, RawValue, Value)
import Morphir.SDK.Bool exposing (false, true)
import Morphir.Value.Error exposing (Error(..))
import Morphir.Value.Native as Native exposing (decodeFun1, decodeMaybe, decodeRaw, encodeMaybeResult, encodeRaw, eval2, eval3)


moduleName : ModuleName
moduleName =
    Path.fromString "Maybe"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Maybe"
              , CustomTypeSpecification [ Name.fromString "a" ]
                    (Dict.fromList
                        [ ( Name.fromString "Just", [ ( [ "value" ], Type.Variable () (Name.fromString "a") ) ] )
                        , ( Name.fromString "Nothing", [] )
                        ]
                    )
                    |> Documented "Type that represents an optional value."
              )
            ]
    , values =
        Dict.fromList
            [ vSpec "andThen"
                [ ( "f", tFun [ tVar "a" ] (maybeType () (tVar "b")) )
                , ( "maybe", maybeType () (tVar "a") )
                ]
                (maybeType () (tVar "b"))
            , vSpec "map"
                [ ( "f", tFun [ tVar "a" ] (tVar "b") )
                , ( "maybe", maybeType () (tVar "a") )
                ]
                (maybeType () (tVar "b"))
            , vSpec "map2"
                [ ( "f", tFun [ tVar "a", tVar "b" ] (tVar "r") )
                , ( "maybe1", maybeType () (tVar "a") )
                , ( "maybe2", maybeType () (tVar "b") )
                ]
                (maybeType () (tVar "r"))
            , vSpec "map3"
                [ ( "f", tFun [ tVar "a", tVar "b", tVar "c" ] (tVar "r") )
                , ( "maybe1", maybeType () (tVar "a") )
                , ( "maybe2", maybeType () (tVar "b") )
                , ( "maybe3", maybeType () (tVar "c") )
                ]
                (maybeType () (tVar "r"))
            , vSpec "map4"
                [ ( "f", tFun [ tVar "a", tVar "b", tVar "c", tVar "d" ] (tVar "r") )
                , ( "maybe1", maybeType () (tVar "a") )
                , ( "maybe2", maybeType () (tVar "b") )
                , ( "maybe3", maybeType () (tVar "c") )
                , ( "maybe4", maybeType () (tVar "d") )
                ]
                (maybeType () (tVar "r"))
            , vSpec "map5"
                [ ( "f", tFun [ tVar "a", tVar "b", tVar "c", tVar "d", tVar "e" ] (tVar "r") )
                , ( "maybe1", maybeType () (tVar "a") )
                , ( "maybe2", maybeType () (tVar "b") )
                , ( "maybe3", maybeType () (tVar "c") )
                , ( "maybe4", maybeType () (tVar "d") )
                , ( "maybe5", maybeType () (tVar "e") )
                ]
                (maybeType () (tVar "r"))
            , vSpec "withDefault"
                [ ( "default", tVar "a" )
                , ( "maybe", maybeType () (tVar "a") )
                ]
                (tVar "a")
            , vSpec "hasValue"
                [ ( "maybe", maybeType () (tVar "a") )
                ]
                (boolType ())
            ]
        , doc = Just "Contains the Maybe type (representing optional values), and related functions."
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
                                    Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) value ->
                                        eval (Value.Apply () fun value)

                                    Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ) ->
                                        Ok (nothing ())

                                    _ ->
                                        Err (UnexpectedArguments [ evaluatedArg1 ])
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "withDefault", eval2 Maybe.withDefault decodeRaw (decodeMaybe decodeRaw) encodeRaw )
    , ( "map", eval2 Maybe.map (decodeFun1 encodeRaw decodeRaw) (decodeMaybe decodeRaw) encodeMaybeResult )
    , ( "map2"
      , \eval args ->
            case args of
                [ fun, arg1, arg2 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                eval arg2
                                    |> Result.andThen
                                        (\evaluatedArg2 ->
                                            case ( evaluatedArg1, evaluatedArg2 ) of
                                                ( Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) value1, Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) value2 ) ->
                                                    eval (Value.Apply () (Value.Apply () fun value1) value2)

                                                ( _, Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ) ) ->
                                                    Ok (nothing ())

                                                ( Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ), _ ) ->
                                                    Ok (nothing ())

                                                _ ->
                                                    Err (UnexpectedArguments [ evaluatedArg1, evaluatedArg2 ])
                                        )
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "map3"
      , \eval args ->
            case args of
                [ fun, arg1, arg2, arg3 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                eval arg2
                                    |> Result.andThen
                                        (\evaluatedArg2 ->
                                            eval arg3
                                                |> Result.andThen
                                                    (\evaluatedArg3 ->
                                                        case ( evaluatedArg1, evaluatedArg2, evaluatedArg3 ) of
                                                            ( Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) value1, Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) value2, Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) value3 ) ->
                                                                eval (Value.Apply () (Value.Apply () (Value.Apply () fun value1) value2) value3)

                                                            ( _, _, Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ) ) ->
                                                                Ok (nothing ())

                                                            ( _, Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ), _ ) ->
                                                                Ok (nothing ())

                                                            ( Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ), _, _ ) ->
                                                                Ok (nothing ())

                                                            _ ->
                                                                Err (UnexpectedArguments [ evaluatedArg1, evaluatedArg2, evaluatedArg3 ])
                                                    )
                                        )
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "map4"
      , \eval args ->
            case args of
                [ fun, arg1, arg2, arg3, arg4 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                eval arg2
                                    |> Result.andThen
                                        (\evaluatedArg2 ->
                                            eval arg3
                                                |> Result.andThen
                                                    (\evaluatedArg3 ->
                                                        eval arg4
                                                            |> Result.andThen
                                                                (\evaluatedArg4 ->
                                                                    case [ evaluatedArg1, evaluatedArg2, evaluatedArg3, evaluatedArg4 ] of
                                                                        [ Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) value1, Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) value2, Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) value3, Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) value4 ] ->
                                                                            eval (Value.Apply () (Value.Apply () (Value.Apply () (Value.Apply () fun value1) value2) value3) value4)

                                                                        [ _, _, _, Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ) ] ->
                                                                            Ok (nothing ())

                                                                        [ _, _, Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ), _ ] ->
                                                                            Ok (nothing ())

                                                                        [ _, Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ), _, _ ] ->
                                                                            Ok (nothing ())

                                                                        [ Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ), _, _, _ ] ->
                                                                            Ok (nothing ())

                                                                        _ ->
                                                                            Err (UnexpectedArguments [ evaluatedArg1, evaluatedArg2, evaluatedArg3, evaluatedArg4 ])
                                                                )
                                                    )
                                        )
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "map5"
      , \eval args ->
            case args of
                [ fun, arg1, arg2, arg3, arg4, arg5 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                eval arg2
                                    |> Result.andThen
                                        (\evaluatedArg2 ->
                                            eval arg3
                                                |> Result.andThen
                                                    (\evaluatedArg3 ->
                                                        eval arg4
                                                            |> Result.andThen
                                                                (\evaluatedArg4 ->
                                                                    eval arg5
                                                                        |> Result.andThen
                                                                            (\evaluatedArg5 ->
                                                                                case [ evaluatedArg1, evaluatedArg2, evaluatedArg3, evaluatedArg4, evaluatedArg5 ] of
                                                                                    [ Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) value1, Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) value2, Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) value3, Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) value4, Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) value5 ] ->
                                                                                        eval (Value.Apply () (Value.Apply () (Value.Apply () (Value.Apply () (Value.Apply () fun value1) value2) value3) value4) value5)

                                                                                    [ _, _, _, _, Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ) ] ->
                                                                                        Ok (nothing ())

                                                                                    [ _, _, _, Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ), _ ] ->
                                                                                        Ok (nothing ())

                                                                                    [ _, _, Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ), _, _ ] ->
                                                                                        Ok (nothing ())

                                                                                    [ _, Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ), _, _, _ ] ->
                                                                                        Ok (nothing ())

                                                                                    [ Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ), _, _, _, _ ] ->
                                                                                        Ok (nothing ())

                                                                                    _ ->
                                                                                        Err (UnexpectedArguments [ evaluatedArg1, evaluatedArg2, evaluatedArg3, evaluatedArg4, evaluatedArg5 ])
                                                                            )
                                                                )
                                                    )
                                        )
                            )

                _ ->
                    Err (UnexpectedArguments args)
      ),
      ( "hasValue"
        ,\eval args ->
            case args of
                [ arg1 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                case evaluatedArg1 of
                                    Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) _ ->
                                        Ok ( (Value.Literal () (BoolLiteral true) )  )
                                    (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] )) ->
                                        Ok ( (Value.Literal () (BoolLiteral false) )  )
                                    _ ->
                                        Err (UnexpectedArguments args)
                            )
                _ ->
                    Err (UnexpectedArguments args)
      )
    ]


maybeType : a -> Type a -> Type a
maybeType attributes itemType =
    Reference attributes (toFQName moduleName "Maybe") [ itemType ]


just : va -> Value ta va -> Value ta va
just va v =
    Value.Apply va (Value.Constructor va (toFQName moduleName "Just")) v


nothing : va -> Value ta va
nothing va =
    Value.Constructor va (toFQName moduleName "Nothing")
