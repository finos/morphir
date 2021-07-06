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


module Morphir.IR.SDK.List exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Basics exposing (boolType, intType, orderType)
import Morphir.IR.SDK.Common exposing (tFun, tVar, toFQName, vSpec)
import Morphir.IR.SDK.Maybe exposing (maybeType)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Value.Error exposing (Error(..))
import Morphir.Value.Native as Native exposing (decodeFun1, decodeList, decodeLiteral, decodeRaw, encodeList, encodeLiteral, encodeRaw, encodeResultList, eval2, intLiteral)


moduleName : ModuleName
moduleName =
    Path.fromString "List"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "List", OpaqueTypeSpecification [ [ "a" ] ] |> Documented "Type that represents a list of values." )
            ]
    , values =
        Dict.fromList
            [ vSpec "singleton" [ ( "a", tVar "a" ) ] (listType () (tVar "a"))
            , vSpec "repeat" [ ( "n", intType () ), ( "a", tVar "a" ) ] (listType () (tVar "a"))
            , vSpec "range" [ ( "from", intType () ), ( "to", intType () ) ] (listType () (intType ()))
            , vSpec "cons" [ ( "head", tVar "a" ), ( "tail", listType () (tVar "a") ) ] (listType () (tVar "a"))
            , vSpec "map" [ ( "f", tFun [ tVar "a" ] (tVar "b") ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "b"))
            , vSpec "indexedMap" [ ( "f", tFun [ intType (), tVar "a" ] (tVar "b") ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "b"))
            , vSpec "foldl" [ ( "f", tFun [ tVar "a", tVar "b" ] (tVar "b") ), ( "z", tVar "b" ), ( "list", listType () (tVar "a") ) ] (tVar "b")
            , vSpec "foldr" [ ( "f", tFun [ tVar "a", tVar "b" ] (tVar "b") ), ( "z", tVar "b" ), ( "list", listType () (tVar "a") ) ] (tVar "b")
            , vSpec "filter" [ ( "f", tFun [ tVar "a" ] (boolType ()) ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "a"))
            , vSpec "filterMap" [ ( "f", tFun [ tVar "a" ] (maybeType () (tVar "b")) ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "b"))
            , vSpec "length" [ ( "list", listType () (tVar "a") ) ] (intType ())
            , vSpec "reverse" [ ( "list", listType () (tVar "a") ) ] (listType () (tVar "a"))
            , vSpec "member" [ ( "ref", tVar "a" ), ( "list", listType () (tVar "a") ) ] (boolType ())
            , vSpec "all" [ ( "f", tFun [ tVar "a" ] (boolType ()) ), ( "list", listType () (tVar "a") ) ] (boolType ())
            , vSpec "any" [ ( "f", tFun [ tVar "a" ] (boolType ()) ), ( "list", listType () (tVar "a") ) ] (boolType ())
            , vSpec "maximum" [ ( "list", listType () (tVar "comparable") ) ] (maybeType () (tVar "comparable"))
            , vSpec "minimum" [ ( "list", listType () (tVar "comparable") ) ] (maybeType () (tVar "comparable"))
            , vSpec "sum" [ ( "list", listType () (tVar "number") ) ] (tVar "number")
            , vSpec "product" [ ( "list", listType () (tVar "number") ) ] (tVar "number")
            , vSpec "append" [ ( "l1", listType () (tVar "a") ), ( "l2", listType () (tVar "a") ) ] (listType () (tVar "a"))
            , vSpec "concat" [ ( "lists", listType () (listType () (tVar "a")) ) ] (listType () (tVar "a"))
            , vSpec "concatMap" [ ( "f", tFun [ tVar "a" ] (listType () (tVar "b")) ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "b"))
            , vSpec "intersperse" [ ( "a", tVar "a" ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "a"))
            , vSpec "map2"
                [ ( "f", tFun [ tVar "a", tVar "b" ] (tVar "r") )
                , ( "list1", listType () (tVar "a") )
                , ( "list2", listType () (tVar "b") )
                ]
                (listType () (tVar "r"))
            , vSpec "map3"
                [ ( "f", tFun [ tVar "a", tVar "b", tVar "c" ] (tVar "r") )
                , ( "list1", listType () (tVar "a") )
                , ( "list2", listType () (tVar "b") )
                , ( "list3", listType () (tVar "c") )
                ]
                (listType () (tVar "r"))
            , vSpec "map4"
                [ ( "f", tFun [ tVar "a", tVar "b", tVar "c", tVar "d" ] (tVar "r") )
                , ( "list1", listType () (tVar "a") )
                , ( "list2", listType () (tVar "b") )
                , ( "list3", listType () (tVar "c") )
                , ( "list4", listType () (tVar "d") )
                ]
                (listType () (tVar "r"))
            , vSpec "map5"
                [ ( "f", tFun [ tVar "a", tVar "b", tVar "c", tVar "d", tVar "e" ] (tVar "r") )
                , ( "list1", listType () (tVar "a") )
                , ( "list2", listType () (tVar "b") )
                , ( "list3", listType () (tVar "c") )
                , ( "list4", listType () (tVar "d") )
                , ( "list5", listType () (tVar "e") )
                ]
                (listType () (tVar "r"))
            , vSpec "sort" [ ( "list", listType () (tVar "comparable") ) ] (listType () (tVar "comparable"))
            , vSpec "sortBy" [ ( "f", tFun [ tVar "a" ] (tVar "comparable") ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "a"))
            , vSpec "sortWith" [ ( "f", tFun [ tVar "a", tVar "a" ] (orderType ()) ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "a"))
            , vSpec "isEmpty" [ ( "list", listType () (tVar "a") ) ] (boolType ())
            , vSpec "head" [ ( "list", listType () (tVar "a") ) ] (maybeType () (tVar "a"))
            , vSpec "tail" [ ( "list", listType () (tVar "a") ) ] (maybeType () (listType () (tVar "a")))
            , vSpec "take" [ ( "n", intType () ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "a"))
            , vSpec "drop" [ ( "n", intType () ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "a"))
            , vSpec "partition" [ ( "f", tFun [ tVar "a" ] (boolType ()) ), ( "list", listType () (tVar "a") ) ] (Type.Tuple () [ listType () (tVar "a"), listType () (tVar "a") ])
            , vSpec "unzip" [ ( "list", listType () (Type.Tuple () [ tVar "a", tVar "b" ]) ) ] (Type.Tuple () [ listType () (tVar "a"), listType () (tVar "b") ])
            ]
    }


listType : a -> Type a -> Type a
listType attributes itemType =
    Type.Reference attributes (toFQName moduleName "List") [ itemType ]


construct : a -> Value ta a
construct a =
    Value.Reference a (toFQName moduleName "construct")


nativeAppend : Native.Function
nativeAppend eval args =
    case args of
        [ arg1, arg2 ] ->
            eval arg1
                |> Result.andThen
                    (\evaluatedArg1 ->
                        case evaluatedArg1 of
                            Value.List _ items1 ->
                                eval arg2
                                    |> Result.andThen
                                        (\evaluatedArg2 ->
                                            case evaluatedArg2 of
                                                Value.List _ items2 ->
                                                    Ok (Value.List () (List.append items1 items2))

                                                _ ->
                                                    Err (UnexpectedArguments args)
                                        )

                            _ ->
                                Err (UnexpectedArguments args)
                    )

        _ ->
            Err (UnexpectedArguments args)


nativeFunctions : List ( String, Native.Function )
nativeFunctions =
    [ ( "sum"
      , Native.unaryStrict
            (\eval arg ->
                case arg of
                    Value.List _ value ->
                        value
                            |> List.foldl
                                (\nextElem resultSoFar ->
                                    resultSoFar
                                        |> Result.andThen
                                            (\resultValue ->
                                                eval
                                                    (Value.Apply ()
                                                        (Value.Apply ()
                                                            (Value.Reference () (fqn "Morphir.SDK" "Basics" "add"))
                                                            nextElem
                                                        )
                                                        resultValue
                                                    )
                                            )
                                )
                                (Ok (Value.Literal () (IntLiteral 0)))

                    _ ->
                        Err (UnexpectedArguments [ arg ])
            )
      )
    , ( "map", eval2 List.map (decodeFun1 encodeRaw decodeRaw) (decodeList decodeRaw) encodeResultList )
    , ( "append", eval2 List.append (decodeList decodeRaw) (decodeList decodeRaw) (encodeList encodeRaw) )
    , ( "range", eval2 List.range (decodeLiteral intLiteral) (decodeLiteral intLiteral) (encodeList (encodeLiteral IntLiteral)) )
    ]
